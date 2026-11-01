import 'package:flutter/material.dart';

import '../../models/extra_capture.dart';
import '../../models/scan_session.dart';

/// After the three required photos (and the declaration): the optional
/// CORNER and ELEVATED photos, then the upload. Nothing here is required;
/// UPLOAD AND COUNT is always available.
class ExtraViewsPane extends StatefulWidget {
  const ExtraViewsPane({
    super.key,
    required this.session,
    required this.onCorner,
    required this.onElevated,
    required this.onEditTaps,
    required this.onRemove,
    required this.onUpload,
  });

  final ScanSession session;

  /// Take (or retake) the CORNER photo from `front_left` or `front_right`.
  final ValueChanged<String> onCorner;
  final VoidCallback onElevated;
  final VoidCallback onEditTaps;
  final ValueChanged<ExtraView> onRemove;
  final VoidCallback onUpload;

  @override
  State<ExtraViewsPane> createState() => _ExtraViewsPaneState();
}

class _ExtraViewsPaneState extends State<ExtraViewsPane> {
  late String _side =
      widget.session.extraFor(ExtraView.corner)?.side ?? kCornerFrontLeft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final corner = widget.session.extraFor(ExtraView.corner);
    final elevated = widget.session.extraFor(ExtraView.elevated);
    final taps = elevated?.taps;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(
          'OPTIONAL EXTRA PHOTOS',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'The three required photos are done. These photos are optional; '
          'they can settle the block size and the stacks the faces cannot '
          'show.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add a CORNER photo (optional)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Two adjoining faces in one photo, from a front corner.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: kCornerFrontLeft,
                      label: Text('FRONT LEFT'),
                    ),
                    ButtonSegment(
                      value: kCornerFrontRight,
                      label: Text('FRONT RIGHT'),
                    ),
                  ],
                  selected: {_side},
                  onSelectionChanged: (s) => setState(() => _side = s.first),
                ),
                const SizedBox(height: 8),
                if (corner != null)
                  Text(
                    'Taken from the '
                    '${(corner.side ?? '').replaceAll('_', ' ')} corner.',
                    key: const ValueKey('corner-taken'),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('add-corner'),
                      onPressed: () => widget.onCorner(_side),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        corner == null
                            ? 'ADD CORNER PHOTO'
                            : 'RETAKE CORNER PHOTO',
                      ),
                    ),
                    if (corner != null)
                      TextButton(
                        onPressed: () => widget.onRemove(ExtraView.corner),
                        child: const Text('REMOVE'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add an ELEVATED photo (optional)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'From a ladder or with your arms raised, looking down on the '
                  'block top. You then mark what each cell shows.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (elevated != null)
                  Text(
                    taps == null
                        ? 'Taken; the top has not been read.'
                        : 'Taken; ${taps.cells.length} of ${taps.x * taps.y} '
                              'cells read.',
                    key: const ValueKey('elevated-taken'),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('add-elevated'),
                      onPressed: widget.onElevated,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        elevated == null
                            ? 'ADD ELEVATED PHOTO'
                            : 'RETAKE ELEVATED PHOTO',
                      ),
                    ),
                    if (elevated != null)
                      TextButton(
                        key: const ValueKey('edit-taps'),
                        onPressed: widget.onEditTaps,
                        child: const Text('READ THE TOP'),
                      ),
                    if (elevated != null)
                      TextButton(
                        onPressed: () => widget.onRemove(ExtraView.elevated),
                        child: const Text('REMOVE'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('extras-upload'),
          onPressed: widget.onUpload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('UPLOAD AND COUNT'),
        ),
      ],
    );
  }
}
