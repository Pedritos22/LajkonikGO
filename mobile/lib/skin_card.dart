import 'package:flutter/material.dart';

import 'lajkonik_avatar.dart';
import 'rewards.dart';

class SkinCard extends StatelessWidget {
  const SkinCard({super.key, required this.rewards, required this.demo});
  final RewardsController rewards;
  final bool demo;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: rewards,
    builder: (context, _) {
      final owned = rewards.ownsLajkonik(demo);
      final selected = rewards.usesLajkonik(demo);
      final missing = rewards.lajkonikPrice - rewards.balance(demo);
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFEBEFDF),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TWÓJ WYGLĄD NA MAPIE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const LajkonikAvatar(size: 76),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zostań Lajkonikiem',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selected
                            ? 'Lajkonik jest Twoim znacznikiem pozycji.'
                            : 'Zmień znacznik swojej pozycji w Lajkonika. Odblokowanie na stałe za ${rewards.lajkonikPrice} punktów.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${rewards.loaded ? rewards.balance(demo) : '—'} pkt${demo ? ' demo' : ''} · ${owned ? 'Wygląd odblokowany' : 'Koszt: ${rewards.lajkonikPrice} pkt'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (rewards.loaded && !owned && missing > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Brakuje $missing pkt. Zdobądź je, obracając punkty przygody.',
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    !rewards.loaded ||
                        rewards.busy ||
                        (!owned && missing > 0) ||
                        selected
                    ? null
                    : () async {
                        if (owned) {
                          await rewards.selectLajkonik(demo, true);
                        } else if (await rewards.buyLajkonik(demo) &&
                            context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Lajkonik odblokowany! Znajdziesz go na mapie.',
                              ),
                            ),
                          );
                        }
                      },
                icon: Icon(
                  selected
                      ? Icons.check_circle_outline
                      : owned
                      ? Icons.person_pin_circle_outlined
                      : Icons.stars_rounded,
                ),
                label: Text(
                  selected
                      ? 'Lajkonik wybrany'
                      : owned
                      ? 'Użyj Lajkonika'
                      : 'Odblokuj · ${rewards.lajkonikPrice} pkt',
                ),
              ),
            ),
            if (selected)
              Center(
                child: TextButton(
                  onPressed: rewards.busy
                      ? null
                      : () => rewards.selectLajkonik(demo, false),
                  child: const Text('Użyj zwykłego znacznika'),
                ),
              ),
            if (demo)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Wygląd demo jest oddzielony od wyglądu kupionego za punkty GPS.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            if (rewards.busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (rewards.error != null)
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  rewards.error!,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (rewards.error != null)
              TextButton(
                onPressed: rewards.busy ? null : rewards.load,
                child: const Text('Spróbuj ponownie'),
              ),
          ],
        ),
      );
    },
  );
}
