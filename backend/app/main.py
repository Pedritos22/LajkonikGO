import asyncio
from datetime import datetime
import os
from typing import Literal

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from app.city_data import city
from app.geo import meters
from app.road_routes import road_plan
from app.transit import transit

app = FastAPI(title="LajkonikGO API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[v for v in os.getenv('FRONTEND_ORIGINS', '').split(',') if v],
    allow_origin_regex=r'https?://(localhost|127\.0\.0\.1)(:\d+)?',
    allow_methods=['GET', 'POST'],
    allow_headers=['Content-Type'],
)


class Coordinate(BaseModel):
    latitude: float = Field(ge=49.8, le=50.3)
    longitude: float = Field(ge=19.5, le=20.4)

    def pair(self):
        return [self.latitude, self.longitude]


class RouteRequest(BaseModel):
    origin: Coordinate
    destination: Coordinate
    mode: Literal['walk', 'bike', 'transit', 'car', 'wheelchair']


@app.get('/city-data')
async def city_sources():
    bikes, works, barriers, alerts = await asyncio.gather(
        city.bikes([50.0544, 19.9354], [50.0679, 19.9454]), city.works(), city.barriers(), city.transit_alerts())
    return dict(sources=[bikes[1], works[1], barriers[1], *alerts[1]],
                works=works[0], bicycle_features=len(bikes[0]), alerts=alerts[0])


@app.post('/routes')
async def routes(request: RouteRequest):
    origin, destination = request.origin.pair(), request.destination.pair()
    if meters(origin, destination) > 40000:
        raise HTTPException(422, 'Wybierz trasę w Krakowie i okolicy, do 40 km.')
    bikes, works, barriers = await asyncio.gather(city.bikes(origin, destination), city.works(), city.barriers())
    if meters(origin, destination) < 10:
        return dict(mode=request.mode, geometry=[origin, destination], distance_m=0, duration_s=0,
                    steps=[], warnings=['Jesteś już przy celu.'], sources=[bikes[1], works[1], barriers[1]], bicycle=None)
    if request.mode == 'transit':
        alerts, alert_sources = await city.transit_alerts()
        result = await transit.plan(origin, destination, alerts)
        result['sources'].extend(alert_sources)
    else:
        result = await road_plan(origin, destination, request.mode, bikes[0], barriers[0], works[0])
    result['mode'] = request.mode
    if request.mode in ('bike', 'wheelchair') and bikes[1].get('status') != 'available':
        result['bicycle'] = None
        result['warnings'].append('Brak pełnych danych ZTP: nie obliczono pokrycia trasą rowerową ani oceny nawierzchni.')
    result['sources'].extend([bikes[1], works[1]])
    if request.mode == 'wheelchair':
        result['sources'].append(barriers[1])
    result['city_works'] = works[0]
    return result


@app.get("/health")
def health_check():
    return {"status": "ok"}
