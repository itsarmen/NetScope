/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'format.dart';
import 'hosts_dialog.dart';
import 'widgets.dart';

Future<void> showEventDialog(
  BuildContext context,
  AppState state,
  NetworkEvent event,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _EventDialog(state: state, event: event),
  );
}

class _EventDialog extends StatelessWidget {
  const _EventDialog({required this.state, required this.event});

  final AppState state;
  final NetworkEvent event;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              event.processDisplay,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          RiskBadge(severity: event.severity, score: event.riskScore),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kv('Time', event.dateTimeDisplay),
              _kv('Direction', event.direction.label),
              _kv('Process', event.processDisplay),
              _kv('Process path', event.processPath.isEmpty ? '—' : event.processPath),
              _kv('PID', '${event.pid}'),
              _kv('Protocol', event.protocol.toUpperCase()),
              _kv('State', event.state.isEmpty ? '—' : event.state),
              _kv('Local', event.localDisplay.isEmpty ? '—' : event.localDisplay),
              _kv('Remote', event.remoteDisplay),
              _kv('Domain', event.domain.isEmpty ? '—' : event.domain),
              _kv('Bytes sent', humanBytes(event.bytesSent)),
              _kv('Bytes received', humanBytes(event.bytesReceived)),
              _kv('Duration', formatDuration(event.durationMs)),
              const SizedBox(height: 16),
              const SectionTitle('Detection'),
              if (event.reasons.isEmpty)
                const Text(
                  'No risk signals were triggered for this event.',
                  style: TextStyle(
                    fontSize: AppSizes.fontBody,
                    color: AppColors.secondary,
                  ),
                )
              else
                for (final reason in event.reasons)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.gpp_maybe_outlined,
                          size: 16,
                          color: severityColor(event.severity),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reason.label,
                            style: const TextStyle(
                              fontSize: AppSizes.fontBody,
                            ),
                          ),
                        ),
                        Text(
                          '+${reason.weight}',
                          style: TextStyle(
                            fontSize: AppSizes.fontSecondary,
                            color: severityColor(event.severity),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showHostsDialog(
            context,
            initialHostname: event.domain.isEmpty ? null : event.domain,
          ),
          child: const Text('Hosts...'),
        ),
        TextButton(
          onPressed: () {
            state.addAllowlist(event);
            Navigator.of(context).pop();
          },
          child: const Text('Allowlist'),
        ),
        TextButton(
          onPressed: () => copyToClipboard(
            context,
            const JsonEncoder.withIndent('  ').convert(event.toJson()),
            'event JSON',
          ),
          child: const Text('Copy JSON'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: AppSizes.fontMono,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
