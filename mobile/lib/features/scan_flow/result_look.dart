import 'package:flutter/material.dart';

/// Icon, colour and words for one result state (`ScanResult.resultStatus`),
/// shared by the result screen and the scan history so they never disagree.
typedef ResultLook = ({IconData icon, Color color, String headline, String label});

ResultLook resultLook(String status) => switch (status) {
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
  // A total, but hidden stacks are computed or two faces differ by a layer.
  'estimated' => const (
    icon: Icons.calculate_outlined,
    color: Color(0xFF8AB4F8),
    headline: 'BLOCK ESTIMATE',
    label: 'ESTIMATE',
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
