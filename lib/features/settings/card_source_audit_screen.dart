import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_state_views.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/repositories/card_source_audit_repository.dart';

class CardSourceAuditScreen extends ConsumerStatefulWidget {
  const CardSourceAuditScreen({super.key});

  @override
  ConsumerState<CardSourceAuditScreen> createState() =>
      _CardSourceAuditScreenState();
}

class _CardSourceAuditScreenState extends ConsumerState<CardSourceAuditScreen> {
  final _cursors = <CardSourceAuditCursor?>[null];
  var _pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final report = ref.watch(cardSourceAuditReportProvider(cursor));
    return Scaffold(
      appBar: AppBar(title: const Text('Card source audit')),
      body: report.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading card source audit',
          ),
        ),
        error: (error, stackTrace) => ErrorStateView(
          message: 'Could not load the card source audit. No data was changed.',
          onRetry: () => ref.invalidate(cardSourceAuditReportProvider(cursor)),
        ),
        data: (value) => _buildReport(context, value),
      ),
    );
  }

  Widget _buildReport(BuildContext context, CardSourceAuditReport report) {
    return ListView(
      padding: AppSpacing.screen.copyWith(
        bottom: BloomBottomInset.contentPadding(context),
      ),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This report uses stored account and transaction details. '
              'A card label does not confirm a credit-card product or who owns it.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Stored sources', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (report.sources.isEmpty)
          const Text('No stored payment sources are available yet.')
        else
          for (final source in report.sources) _SourceAuditCard(source: source),
        if (report.sourcesTruncated)
          const _CoverageNotice(
            text: 'Some source rows are outside this bounded summary.',
          ),
        const SizedBox(height: 20),
        Text(
          'Stored identity conflicts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (report.conflicts.isEmpty)
          const Text(
            'No multi-source conflict is evidenced by currently stored '
            'details. A past merge into one source cannot be reconstructed.',
          )
        else
          for (final conflict in report.conflicts)
            _ConflictAuditCard(conflict: conflict),
        if (report.conflictsTruncated)
          const _CoverageNotice(
            text: 'Additional stored conflicts are outside this summary.',
          ),
        const SizedBox(height: 20),
        Text(
          'Possible card transactions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (report.candidates.isEmpty)
          Text(
            _pageIndex == 0
                ? 'No transactions with a stored card channel were found.'
                : 'No more matching records.',
          )
        else
          for (final candidate in report.candidates)
            _CandidateAuditCard(candidate: candidate),
        if (report.candidatesTruncated)
          _CandidatePageControls(
            canGoBack: _pageIndex > 0,
            onPrevious: _pageIndex > 0 ? _previousPage : null,
            onNext: report.nextCursor == null
                ? null
                : () => _nextPage(report.nextCursor!),
          )
        else if (_pageIndex > 0)
          _CandidatePageControls(
            canGoBack: true,
            onPrevious: _previousPage,
            onNext: null,
          ),
        if (!report.candidatesTruncated && _pageIndex == 0)
          const _CoverageNotice(
            text: 'Candidate rows retain their stored flags and lifecycle. '
                'This audit does not decide financial eligibility.',
          ),
      ],
    );
  }

  void _nextPage(CardSourceAuditCursor cursor) {
    setState(() {
      if (_pageIndex + 1 < _cursors.length) {
        _cursors.removeRange(_pageIndex + 1, _cursors.length);
      }
      _cursors.add(cursor);
      _pageIndex++;
    });
  }

  void _previousPage() {
    setState(() => _pageIndex--);
  }
}

class _SourceAuditCard extends StatelessWidget {
  const _SourceAuditCard({required this.source});

  final CardSourceAuditSource source;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.maskedIdentifier,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('Stored kind: ${source.kind}'),
              Text('Nickname: ${source.nickname}'),
              Text('Institution: ${source.institution}'),
              Text('Stored records: ${source.rowCount}'),
              const Text('Product: unverified · Ownership: unverified'),
              if (source.buckets.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No transaction groups are recorded.'),
                )
              else ...[
                const SizedBox(height: 8),
                for (final bucket in source.buckets)
                  Text(
                    '${bucket.lifecycleState} · ${bucket.currencyLabel}: '
                    '${bucket.rowCount} rows',
                  ),
                if (source.bucketsTruncated)
                  Text(
                    '${source.totalBucketCount - source.buckets.length} '
                    'additional lifecycle/currency groups are omitted; '
                    'the total row count above includes them.',
                  ),
              ],
            ],
          ),
        ),
      );
}

class _ConflictAuditCard extends StatelessWidget {
  const _ConflictAuditCard({required this.conflict});

  final CardSourceAuditConflict conflict;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stored identity conflict · ${conflict.maskedIdentifier}'),
              Text('Stored channel: ${conflict.channel}'),
              Text('Mapped source rows: ${conflict.sourceIdCount}'),
              Text(
                'Recorded institution labels: '
                '${conflict.institutionLabelCount}',
              ),
              if (conflict.hasUnlinkedRows)
                const Text('Some matching rows have no linked source.'),
            ],
          ),
        ),
      );
}

class _CandidateAuditCard extends StatelessWidget {
  const _CandidateAuditCard({required this.candidate});

  final CardSourceAuditCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      candidate.timestampMs,
      isUtc: true,
    ).toLocal();
    final flags = <String>[
      if (candidate.isDeleted) 'Deleted',
      if (candidate.isNotTransaction) 'Marked not a transaction',
      if (candidate.isDuplicate) 'Duplicate-linked',
      if (candidate.isAnalyticsExcluded) 'Excluded from analytics',
      if (candidate.ownedTransferId != null) 'Transfer marker recorded',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatSourceAmount(
                candidate.amount,
                currencyCode: candidate.currencyCode,
                currencySymbol: candidate.currencySymbol,
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${candidate.direction} · ${candidate.lifecycleState}'),
            Text('Stored status: ${candidate.status}'),
            Text('Date: ${formatTxnTime(timestamp)}'),
            Text('Currency: ${candidate.currencyLabel}'),
            Text('Stored source kind: ${candidate.sourceKind}'),
            Text('Identifier: ${candidate.maskedIdentifier}'),
            Text('Nickname: ${candidate.nickname}'),
            Text('Institution: ${candidate.institution}'),
            const Text('Product: unverified · Ownership: unverified'),
            if (flags.isNotEmpty)
              Text('Stored flags: ${flags.join(' · ')}')
            else
              const Text(
                'No exclusion flags recorded; this is not an eligibility result.',
              ),
            if (!candidate.sourceAvailable)
              const Text('A stored payment source is unavailable.'),
          ],
        ),
      ),
    );
  }
}

class _CandidatePageControls extends StatelessWidget {
  const _CandidatePageControls({
    required this.canGoBack,
    required this.onPrevious,
    required this.onNext,
  });

  final bool canGoBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (canGoBack)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              onPressed: onPrevious,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Previous'),
            ),
          if (onNext != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('More transactions'),
            ),
        ],
      );
}

class _CoverageNotice extends StatelessWidget {
  const _CoverageNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}
