import 'package:flutter/material.dart';

/// Icon, colour and words for one result state (`ScanResult.resultStatus`),
/// shared by the result screen and the scan history so they never disagree.
typedef ResultLook = ({IconData icon, Color color, String headline, String label});

/// [basis] is the block's `confirmed_basis`; it is only read for
/// `confirmed`, which always names what it rests on. History rows do not
/// keep the basis: a confirmed block always rests on a declaration that
/// agreed with the faces, so their label says so.
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
      // Visible stacks verified; the interior rests on the declaration or
      // the top view. Never called exact or physically verified.
      'confirmed' => (
        icon: Icons.fact_check_outlined,
        color: const Color(0xFFB39DDB),
        headline: confirmedHeadline(basis),
        label: basis.contains('top_view') && !basis.contains('declaration')
            ? 'CONFIRMED (TOP VIEW)'
            : 'CONFIRMED (DECLARED)',
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

/// The `confirmed` headline, naming its basis, for example "CONFIRMED:
/// VISIBLE STACKS VERIFIED, INTERIOR DECLARED".
String confirmedHeadline(List<String> basis) {
  final declared = basis.contains('declaration');
  final topView = basis.contains('top_view');
  final interior = switch ((declared, topView)) {
    (true, true) => 'INTERIOR DECLARED AND SEEN FROM ABOVE',
    (true, false) => 'INTERIOR DECLARED',
    (false, true) => 'INTERIOR SEEN FROM ABOVE',
    (false, false) => 'INTERIOR BASIS NOT REPORTED',
  };
  return 'CONFIRMED: VISIBLE STACKS VERIFIED, $interior';
}

/// A history row whose stored status says nothing about the scan (saved by
/// an app before 0.4.12, see `ScanHistoryEntry.recordedByOlderApp`).
const ResultLook unknownLook = (
  icon: Icons.help_outline,
  color: Colors.blueGrey,
  headline: 'UNKNOWN',
  label: 'UNKNOWN',
);
