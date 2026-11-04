import 'package:flutter/material.dart';

/// Icon, colour and words for one result state (`ScanResult.resultStatus`),
/// shared by the result screen and the scan history so they never disagree.
typedef ResultLook = ({IconData icon, Color color, String headline, String label});

/// [basis] is a 0.5 block's `confirmed_basis`; it is no longer shown. A
/// `confirmed` block (0.5 servers only) rests on hidden stacks that were
/// never counted, so it is shown as the estimate it is, for history rows too.
ResultLook resultLook(String status, {List<String> basis = const []}) =>
    switch (status) {
      'verified' => const (
        icon: Icons.verified_outlined,
        color: Color(0xFF63E6A5),
        headline: 'VERIFIED',
        label: 'VERIFIED',
      ),
      // Every stack seen and the faces agree.
      'exact' => const (
        icon: Icons.verified_outlined,
        color: Color(0xFF63E6A5),
        headline: 'BLOCK COUNTED',
        label: 'COUNTED',
      ),
      // A total, but hidden stacks are assumed or two faces differ by a layer.
      'estimated' => const (
        icon: Icons.calculate_outlined,
        color: Color(0xFF8AB4F8),
        headline: 'BLOCK ESTIMATE',
        label: 'ESTIMATE',
      ),
      // An older server's stronger label for a block with a declared or
      // top-view interior: never exact, never physically verified.
      'confirmed' => const (
        icon: Icons.calculate_outlined,
        color: Color(0xFF8AB4F8),
        headline: 'BLOCK ESTIMATE',
        label: 'ESTIMATE (OLDER SERVER)',
      ),
      _ => const (
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFFFB86B),
        headline: 'RETAKE NEEDED',
        label: 'RETAKE',
      ),
    };

/// A history row whose stored status says nothing about the scan (saved by
/// an app before 0.4.12, see `ScanHistoryEntry.recordedByOlderApp`).
const ResultLook unknownLook = (
  icon: Icons.help_outline,
  color: Colors.blueGrey,
  headline: 'UNKNOWN',
  label: 'UNKNOWN',
);
