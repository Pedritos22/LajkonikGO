import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'places.dart';
import 'rewards.dart';
import 'tracking.dart';

class PointSheet extends StatefulWidget {
  const PointSheet({
    super.key,
    required this.place,
    required this.tracker,
    required this.rewards,
    required this.onPlan,
  });
  final Landmark place;
  final TrackingController tracker;
  final RewardsController rewards;
  final VoidCallback onPlan;
  @override
  State<PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<PointSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool spinning = false;
  bool won = false;
  double drag = 0;

  String? get reason => widget.rewards.reason(
    place: widget.place.name,
    target: widget.place.position,
    demo: widget.tracker.demo,
    position: widget.tracker.position,
    accuracy: widget.tracker.accuracy,
    lastFix: widget.tracker.lastFix,
  );

  Future<void> spin() async {
    if (spinning || reason != null) return;
    setState(() {
      spinning = true;
      won = false;
    });
    try {
      await rotation.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    final awarded = widget.rewards.claim(
      place: widget.place.name,
      target: widget.place.position,
      demo: widget.tracker.demo,
      position: widget.tracker.position,
      accuracy: widget.tracker.accuracy,
      lastFix: widget.tracker.lastFix,
    );
    setState(() {
      spinning = false;
      won = awarded;
    });
  }

  @override
  void dispose() {
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.tracker, widget.rewards]),
    builder: (context, _) {
      final theme = Theme.of(context).colorScheme;
      final available = reason == null;
      final tracker = widget.tracker;
      final distance = tracker.position == null
          ? null
          : const Distance().as(
              LengthUnit.Meter,
              tracker.position!,
              widget.place.position,
            );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tracker.demo ? 'PUNKT PRZYGODY · DEMO' : 'PUNKT PRZYGODY',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Chip(
                avatar: const Icon(Icons.stars_rounded, size: 18),
                label: Text(
                  '${widget.rewards.balance(tracker.demo)} pkt${tracker.demo ? ' demo' : ''}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.place.name,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            widget.place.subtitle,
            style: const TextStyle(color: Color(0xFF7C8478)),
          ),
          const SizedBox(height: 22),
          Center(
            child: GestureDetector(
              onHorizontalDragStart: (_) => drag = 0,
              onHorizontalDragUpdate: (event) {
                drag += event.delta.dx.abs();
                if (drag > 60) spin();
              },
              child: Semantics(
                label: 'Dysk punktu. Przesuń w bok, aby obrócić.',
                child: RotationTransition(
                  turns: Tween<double>(begin: 0, end: 2).animate(
                    CurvedAnimation(
                      parent: rotation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 145,
                    height: 145,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: available || won
                          ? widget.place.color
                          : const Color(0xFFAFB6A9),
                      border: Border.all(
                        color: const Color(0xFFD9EDAC),
                        width: 8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.place.color.withValues(alpha: .18),
                          blurRadius: 25,
                        ),
                      ],
                    ),
                    child: Icon(
                      won ? Icons.stars_rounded : widget.place.icon,
                      size: 67,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              won
                  ? '+50 punktów${tracker.demo ? ' demo' : ''} — świetny przystanek!'
                  : spinning
                  ? 'Obracamy punkt…'
                  : available
                  ? 'Przesuń dysk w bok lub użyj przycisku.'
                  : reason!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: won || available
                    ? theme.primary
                    : const Color(0xFF7C8478),
                height: 1.5,
              ),
            ),
          ),
          if (distance != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  '${distance.round()} m od punktu · zasięg 45 m · GPS ±${tracker.accuracy.round()} m',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C8478),
                  ),
                ),
              ),
            ),
          if (!widget.rewards.persistent)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Zapis lokalny niedostępny — punkty pozostaną tylko w tej sesji.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: available && !spinning ? spin : null,
              icon: const Icon(Icons.rotate_right),
              label: const Text('Obróć punkt · +50 pkt'),
            ),
          ),
          if (!tracker.demo && tracker.position != null)
            Center(
              child: TextButton.icon(
                onPressed: tracker.refreshPosition,
                icon: const Icon(Icons.gps_fixed, size: 17),
                label: const Text('Odśwież pozycję GPS'),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onPlan,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(17),
              ),
              icon: const Icon(Icons.route_outlined),
              label: const Text('Zaplanuj trasę do tego miejsca'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Kolejny obrót po 5 minutach. Punkty demo są oddzielone od punktów zdobytych z GPS.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF7C8478),
              height: 1.5,
            ),
          ),
        ],
      );
    },
  );
}
