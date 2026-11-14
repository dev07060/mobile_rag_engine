import 'package:flutter/material.dart';

import '../e1/app_docs_bundle.dart';
import '../example_model.dart';

/// Ask the E1 app-document questions (docs/perf/e1-app-docs/) and compare
/// hybrid weights on the same top 5 that `ask` would use.
class AppDocsScreen extends StatefulWidget {
  const AppDocsScreen({super.key, required this.model});

  final ExampleModel model;

  @override
  State<AppDocsScreen> createState() => _AppDocsScreenState();
}

class _AppDocsScreenState extends State<AppDocsScreen> {
  E1Bundle? _bundle;
  String _status = 'Loading the question list...';
  bool _busy = false;
  bool _ingested = false;
  String _language = 'en';
  String _intent = 'all';
  E1Question? _question;
  E1Weights _weights = e1WeightPresets.first;
  final _queryController = TextEditingController();
  List<E1Hit>? _hits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bundle = await E1Bundle.load();
      final present = await bundle.collection.listSources();
      setState(() {
        _bundle = bundle;
        _ingested = present.length >= bundle.sources.length;
        _status = _ingested
            ? '${present.length} documents in "$e1CollectionId".'
            : 'Add the ${bundle.sources.length} documents to start.';
      });
    } catch (e) {
      setState(() => _status = 'Could not load the bundle: $e');
    }
  }

  Future<void> _ingest() async {
    final bundle = _bundle;
    if (bundle == null) return;
    setState(() => _busy = true);
    try {
      final added = await bundle.ingest(
        onProgress: (done, total, key) {
          if (mounted) setState(() => _status = 'Adding $done/$total $key');
        },
      );
      setState(() {
        _ingested = true;
        _status = 'Added $added documents (${bundle.sources.length} in total).';
      });
    } catch (e) {
      setState(() => _status = 'Ingest failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    final bundle = _bundle;
    final query = _queryController.text.trim();
    if (bundle == null || query.isEmpty) return;
    setState(() => _busy = true);
    try {
      final q = _question;
      final hits = await bundle.search(
        query,
        weights: _weights,
        goldPassage: q != null && q.query == query ? q.goldPassage : null,
      );
      setState(() => _hits = hits);
    } catch (e) {
      setState(() => _status = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<E1Question> get _visibleQuestions => [
    for (final q in _bundle?.questions ?? const <E1Question>[])
      if (q.language == _language && (_intent == 'all' || q.intent == _intent))
        q,
  ];

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final q = _question;
    return Scaffold(
      appBar: AppBar(title: const Text('App docs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${model.label} · ${model.weightLabel}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(_status)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy || _bundle == null ? null : _ingest,
                child: Text(_ingested ? 'Re-check' : 'Add documents'),
              ),
            ],
          ),
          const Divider(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'ko', label: Text('한국어')),
                ],
                selected: {_language},
                onSelectionChanged: (s) => setState(() {
                  _language = s.first;
                  _question = null;
                }),
              ),
              DropdownButton<String>(
                value: _intent,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All types')),
                  DropdownMenuItem(value: 'lexical', child: Text('Same words')),
                  DropdownMenuItem(
                    value: 'paraphrase',
                    child: Text('Other words'),
                  ),
                  DropdownMenuItem(
                    value: 'no_answer',
                    child: Text('No answer'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _intent = v ?? 'all';
                  _question = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButton<E1Question>(
            isExpanded: true,
            hint: const Text('Pick a question, or type your own below'),
            value: q,
            items: [
              for (final item in _visibleQuestions)
                DropdownMenuItem(
                  value: item,
                  child: Text(
                    '${item.id}  ${item.query}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (item) => setState(() {
              _question = item;
              _queryController.text = item?.query ?? '';
              _hits = null;
            }),
          ),
          TextField(
            controller: _queryController,
            decoration: const InputDecoration(labelText: 'Question'),
            onSubmitted: (_) => _search(),
          ),
          if (q != null && q.query == _queryController.text)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                q.hasAnswer
                    ? 'Answer (${q.goldSourceKey}, ${q.intent}, overlap ${q.measuredClass}): ${q.goldPassage}'
                    : 'No document answers this question.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in e1WeightPresets)
                ChoiceChip(
                  label: Text(w.label),
                  selected: identical(w, _weights),
                  onSelected: (_) {
                    setState(() => _weights = w);
                    if (_hits != null) _search();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || !_ingested ? null : _search,
            icon: const Icon(Icons.search),
            label: const Text('Search top 5'),
          ),
          const SizedBox(height: 16),
          if (_hits != null) ..._buildHits(context, _hits!),
        ],
      ),
    );
  }

  List<Widget> _buildHits(BuildContext context, List<E1Hit> hits) {
    final q = _question;
    final judged = q != null && q.query == _queryController.text;
    final found = hits.any((h) => h.isGold);
    return [
      if (judged)
        Text(
          q.hasAnswer
              ? (found
                    ? '✅ The answer is in the top 5.'
                    : '❌ The answer is not in the top 5.')
              : 'No answer exists; these are the closest passages.',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      if (hits.isEmpty) const Text('No results.'),
      for (final h in hits)
        Card(
          color: h.isGold ? Colors.green.withValues(alpha: 0.12) : null,
          child: ListTile(
            leading: Text('${h.rank}'),
            title: Text(h.sourceKey),
            subtitle: Text(
              h.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
    ];
  }
}
