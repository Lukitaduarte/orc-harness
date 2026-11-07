import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import '../live/daemon_client.dart';
import 'orc_sprite.dart';

/// Marks the first launch as done (kept between launches).
Future<File> _doneFile() async =>
    File('${(await getApplicationSupportDirectory()).path}/onboarded');

/// The onboarding shows on a first launch: not done before and not paired.
Future<bool> needsOnboarding(DaemonClient daemon) async {
  try {
    return !await (await _doneFile()).exists() && !await daemon.hasPairing();
  } catch (_) {
    return false;
  }
}

/// One step: what is asked, why, and the action that brings up macOS's own
/// prompt (null for the welcome).
class _Step {
  const _Step(this.icon, this.title, this.why, this.action);

  final IconData icon;
  final String title;
  final String why;
  final Future<void> Function()? action;
}

/// First launch, one permission at a time: each step says why it is
/// needed, and "Grant" brings up the native prompt for just that one.
class Onboarding extends StatefulWidget {
  const Onboarding({
    super.key,
    required this.daemon,
    required this.requestNotifications,
    required this.onDone,
  });

  final DaemonClient daemon;

  /// Shows the system's notification prompt.
  final Future<void> Function() requestNotifications;
  final VoidCallback onDone;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int _at = 0;
  bool _busy = false;
  String? _error;

  List<_Step> _steps(BuildContext context) {
    final l = context.l10n;
    final d = widget.daemon;
    return [
      _Step(LucideIcons.hand, l.onboardWelcomeTitle, l.onboardWelcomeWhy, null),
      _Step(
        LucideIcons.bell,
        l.onboardNotificationsTitle,
        l.onboardNotificationsWhy,
        widget.requestNotifications,
      ),
      // Only the app that carries its daemon sets one up.
      if (d.local.bundled != null) ...[
        _Step(
          LucideIcons.server,
          l.onboardServiceTitle,
          l.onboardServiceWhy,
          () => d.local.ensureInstalled(),
        ),
        _Step(
          LucideIcons.wifi,
          l.onboardNetworkTitle,
          l.onboardNetworkWhy,
          () async {
            await d.pairLocal();
            if (d.status != LinkStatus.connected) {
              throw Exception(d.error ?? '');
            }
          },
        ),
      ],
    ];
  }

  Future<void> _next(List<_Step> steps, {bool skip = false}) async {
    final action = steps[_at].action;
    if (!skip && action != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await action();
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = '$e';
          });
        }
        return;
      }
    }
    if (!mounted) return;
    if (_at == steps.length - 1) {
      try {
        await (await _doneFile()).create(recursive: true);
      } catch (_) {}
      widget.onDone();
      return;
    }
    setState(() {
      _busy = false;
      _error = null;
      _at++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final steps = _steps(context);
    final step = steps[_at];
    final last = _at == steps.length - 1;
    return Scaffold(
      child: LayoutBuilder(
        builder: (context, box) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: math.min(460, box.maxWidth - 48),
              child: Column(
                key: ValueKey(_at),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (step.action == null)
                    OrcSprite(scale: 5, says: l.orcReady)
                  else
                    Icon(step.icon, size: 36),
                  const Gap(24),
                  Text(step.title).h3(),
                  const Gap(12),
                  Text(step.why).muted(),
                  if (_error != null) ...[
                    const Gap(16),
                    Text(l.onboardFailed(_error!)).small().muted(),
                  ],
                  const Gap(28),
                  Text(l.onboardStep(_at + 1, steps.length)).xSmall().muted(),
                  const Gap(8),
                  // Wraps on a narrow window instead of overflowing.
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (step.action != null)
                        GhostButton(
                          onPressed: _busy
                              ? null
                              : () => _next(steps, skip: true),
                          child: Text(l.onboardNotNow),
                        ),
                      PrimaryButton(
                        onPressed: _busy ? null : () => _next(steps),
                        child: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(),
                              )
                            : Text(
                                step.action == null
                                    ? l.onboardStart
                                    : _error != null
                                    ? l.onboardRetry
                                    : last
                                    ? l.onboardGrantFinish
                                    : l.onboardGrant,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
