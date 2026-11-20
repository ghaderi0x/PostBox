import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/requests/domain/request_models.dart';
import '../../features/streaming/stream_service.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

/// Event log for SSE and WebSocket tabs.
class StreamView extends StatefulWidget {
  const StreamView({super.key, required this.tab});
  final RequestTab tab;

  @override
  State<StreamView> createState() => _StreamViewState();
}

class _StreamViewState extends State<StreamView> {
  final TextEditingController _msg = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(StreamView old) {
    super.didUpdateWidget(old);
    if (widget.tab.events.length != old.tab.events.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _msg.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _label(BuildContext context, StreamEvent e) {
    switch (e.type) {
      case StreamEventType.open:
        return context.t('stream.open');
      case StreamEventType.message:
        return context.t('stream.message');
      case StreamEventType.event:
        return e.label;
      case StreamEventType.sent:
        return context.t('stream.sent');
      case StreamEventType.close:
        return context.t('stream.closed');
      case StreamEventType.error:
        return context.t('stream.error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final c = context.colors;
    final isWs = tab.draft.kind == RequestKind.websocket;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.circle,
                size: 10,
                color: tab.streaming ? c.success : c.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                context.t(
                  tab.streaming ? 'stream.connected' : 'stream.disconnected',
                ),
                style: context.secondary,
              ),
              const Spacer(),
              Text(
                context.t('stream.limit', <String>[
                  '${WorkspaceCubit.maxStreamEvents}',
                ]),
                style: context.secondary,
              ),
            ],
          ),
        ),
        Expanded(
          child: tab.events.isEmpty
              ? EmptyState(
                  icon: isWs ? Icons.swap_horiz : Icons.stream,
                  title: context.t(isWs ? 'stream.emptyWs' : 'stream.emptySse'),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  itemCount: tab.events.length,
                  itemBuilder: (ctx, i) {
                    final e = tab.events[i];
                    final color = e.type == StreamEventType.error
                        ? c.danger
                        : (e.type == StreamEventType.sent
                              ? c.accent
                              : c.textSecondary);
                    var data = e.data;
                    if (data.startsWith('build:')) {
                      final code = data.substring(6);
                      final key = 'err.build.$code';
                      data = ctx.t(key) == key ? code : ctx.t(key);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${_label(ctx, e)}  ${e.time.toLocal().toIso8601String().substring(11, 19)}',
                            style: ctx.timingStyle.copyWith(color: color),
                          ),
                          if (data.isNotEmpty)
                            SelectableText(
                              data,
                              style: ctx.mono.copyWith(fontSize: 12.5),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (isWs)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _msg,
                    enabled: tab.streaming,
                    style: context.mono,
                    decoration: InputDecoration(
                      hintText: context.t('stream.compose'),
                    ),
                    onSubmitted: (v) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: tab.streaming ? _send : null,
                  child: Text(context.t('req.send')),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _send() {
    final text = _msg.text;
    if (text.isEmpty) return;
    context.read<WorkspaceCubit>().sendMessage(widget.tab.id, text);
    _msg.clear();
  }
}
