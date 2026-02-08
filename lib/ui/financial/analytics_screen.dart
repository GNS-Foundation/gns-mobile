/// GNS Analytics Dashboard Screen - Sprint 7
/// 
/// Spending insights, budgets, and savings goals UI.
/// 
/// Location: lib/ui/financial/analytics_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/gns/identity_wallet.dart';
import '../../core/financial/analytics_service.dart';
import '../../core/theme/theme_service.dart';

class AnalyticsScreen extends StatefulWidget {
  final IdentityWallet wallet;
  
  const AnalyticsScreen({super.key, required this.wallet});
  
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _analyticsService = AnalyticsService();
  
  SpendingSummary? _summary;
  List<DailySpending> _dailyData = [];
  List<CategorySpending> _categories = [];
  List<Budget> _budgets = [];
  List<SavingsGoal> _goals = [];
  List<SpendingInsight> _insights = [];
  
  bool _loading = true;
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.thisMonth;
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initialize();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _initialize() async {
    await _analyticsService.initialize(widget.wallet.publicKey!);
    await _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final results = await Future.wait([
        _analyticsService.getSpendingSummary(period: _selectedPeriod),
        _analyticsService.getDailySpending(days: 30),
        _analyticsService.getSpendingByCategory(period: _selectedPeriod),
        _analyticsService.getBudgets(),
        _analyticsService.getSavingsGoals(),
        _analyticsService.getInsights(),
      ]);
      
      setState(() {
        _summary = results[0] as SpendingSummary?;
        _dailyData = results[1] as List<DailySpending>;
        _categories = results[2] as List<CategorySpending>;
        _budgets = results[3] as List<Budget>;
        _goals = results[4] as List<SavingsGoal>;
        _insights = results[5] as List<SpendingInsight>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Analytics'),
        actions: [
          PopupMenuButton<AnalyticsPeriod>(
            icon: const Icon(Icons.calendar_today),
            onSelected: (period) {
              setState(() => _selectedPeriod = period);
              _loadData();
            },
            itemBuilder: (ctx) => AnalyticsPeriod.values
                .where((p) => p != AnalyticsPeriod.custom)
                .map((p) => PopupMenuItem(
                      value: p,
                      child: Text(p.displayName),
                    ))
                .toList(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Categories'),
            Tab(text: 'Budgets'),
            Tab(text: 'Goals'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildCategoriesTab(),
                _buildBudgetsTab(),
                _buildGoalsTab(),
              ],
            ),
    );
  }
  
  // ==================== OVERVIEW TAB ====================
  
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary cards
          _buildSummaryCards(),
          
          const SizedBox(height: 24),
          
          // Spending chart
          _buildSpendingChart(),
          
          const SizedBox(height: 24),
          
          // Insights
          if (_insights.isNotEmpty) ...[
            _buildInsightsSection(),
            const SizedBox(height: 24),
          ],
          
          // Top categories preview
          _buildTopCategoriesPreview(),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCards() {
    if (_summary == null) return const SizedBox.shrink();
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Spent',
                value: '\$${_summary!.totalSpent.toStringAsFixed(2)}',
                icon: Icons.arrow_upward,
                color: AppTheme.error,
                change: _summary!.changePercent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Received',
                value: '\$${_summary!.totalReceived.toStringAsFixed(2)}',
                icon: Icons.arrow_downward,
                color: AppTheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Net Flow',
                value: '\$${_summary!.netFlow.abs().toStringAsFixed(2)}',
                icon: _summary!.isPositiveFlow ? Icons.trending_up : Icons.trending_down,
                color: _summary!.isPositiveFlow ? AppTheme.secondary : AppTheme.error,
                prefix: _summary!.isPositiveFlow ? '+' : '-',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Transactions',
                value: '${_summary!.totalTransactions}',
                icon: Icons.receipt_long,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildSpendingChart() {
    if (_dailyData.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No spending data',
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Spending',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _dailyData
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value.totalSpent))
                        .toList(),
                    isCurved: true,
                    color: AppTheme.primary,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppTheme.primary.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInsightsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Insights',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        ..._insights.take(3).map(_buildInsightCard),
      ],
    );
  }
  
  Widget _buildInsightCard(SpendingInsight insight) {
    IconData icon;
    Color color;
    
    switch (insight.type) {
      case InsightType.tip:
        icon = Icons.lightbulb;
        color = AppTheme.warning;
        break;
      case InsightType.warning:
        icon = Icons.warning;
        color = AppTheme.error;
        break;
      case InsightType.achievement:
        icon = Icons.emoji_events;
        color = AppTheme.secondary;
        break;
      case InsightType.trend:
        icon = Icons.trending_up;
        color = AppTheme.primary;
        break;
      case InsightType.recommendation:
        icon = Icons.recommend;
        color = AppTheme.secondary;
        break;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  insight.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTopCategoriesPreview() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Categories',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              TextButton(
                onPressed: () => _tabController.animateTo(1),
                child: const Text('See All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._categories.take(3).map(_buildCategoryRow),
        ],
      ),
    );
  }
  
  Widget _buildCategoryRow(CategorySpending category) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            category.category.emoji,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.categoryName,
                  style: TextStyle(color: AppTheme.textPrimary(context)),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: category.percentOfTotal / 100,
                    minHeight: 4,
                    backgroundColor: AppTheme.divider(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '\$${category.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
  
  // ==================== CATEGORIES TAB ====================
  
  Widget _buildCategoriesTab() {
    if (_categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📊', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No spending data',
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
          ],
        ),
      );
    }
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pie chart
        _buildCategoryPieChart(),
        const SizedBox(height: 24),
        
        // Category list
        ..._categories.map(_buildCategoryCard),
      ],
    );
  }
  
  Widget _buildCategoryPieChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 50,
          sections: _categories.take(5).toList().asMap().entries.map((e) {
            final colors = [
              AppTheme.primary,
              AppTheme.secondary,
              AppTheme.warning,
              AppTheme.error,
              Colors.purple,
            ];
            return PieChartSectionData(
              value: e.value.percentOfTotal,
              color: colors[e.key % colors.length],
              radius: 50,
              title: '${e.value.percentOfTotal.toStringAsFixed(0)}%',
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  Widget _buildCategoryCard(CategorySpending category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(category.category.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.categoryName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  '${category.transactionCount} transactions',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${category.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              if (category.changePercent != null)
                Text(
                  '${category.changePercent! >= 0 ? '+' : ''}${category.changePercent!.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: category.isIncreased ? AppTheme.error : AppTheme.secondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  // ==================== BUDGETS TAB ====================
  
  Widget _buildBudgetsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Add budget button
        OutlinedButton.icon(
          onPressed: _showCreateBudgetDialog,
          icon: const Icon(Icons.add),
          label: const Text('Create Budget'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        
        if (_budgets.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  const Text('💰', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    'No budgets yet',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a budget to track your spending',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._budgets.map(_buildBudgetCard),
      ],
    );
  }
  
  Widget _buildBudgetCard(Budget budget) {
    final progressColor = budget.isOverBudget
        ? AppTheme.error
        : budget.isNearLimit
            ? AppTheme.warning
            : AppTheme.secondary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                budget.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              if (budget.isOverBudget)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Over Budget',
                    style: TextStyle(
                      color: AppTheme.error,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${budget.spent.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              Text(
                'of \$${budget.amount.toStringAsFixed(2)}',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: budget.percentUsed.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.divider(context),
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(budget.percentUsed * 100).toStringAsFixed(0)}% used',
                style: TextStyle(
                  color: AppTheme.textMuted(context),
                  fontSize: 12,
                ),
              ),
              Text(
                '\$${budget.remaining.toStringAsFixed(2)} left',
                style: TextStyle(
                  color: budget.remaining >= 0 ? AppTheme.secondary : AppTheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showCreateBudgetDialog() {
    // TODO: Implement budget creation dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Budget creation coming soon!')),
    );
  }
  
  // ==================== GOALS TAB ====================
  
  Widget _buildGoalsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          onPressed: _showCreateGoalDialog,
          icon: const Icon(Icons.add),
          label: const Text('Create Savings Goal'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        
        if (_goals.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    'No savings goals',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set a goal and start saving!',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._goals.map(_buildGoalCard),
      ],
    );
  }
  
  Widget _buildGoalCard(SavingsGoal goal) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (goal.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    goal.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('🎯', style: TextStyle(fontSize: 24)),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    if (goal.targetDate != null)
                      Text(
                        '${goal.daysRemaining} days left',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (goal.isCompleted)
                const Icon(Icons.check_circle, color: AppTheme.secondary),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${goal.currentAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              Text(
                'of \$${goal.targetAmount.toStringAsFixed(2)}',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: goal.progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.divider(context),
              valueColor: const AlwaysStoppedAnimation(AppTheme.secondary),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(goal.progress * 100).toStringAsFixed(0)}% complete',
                style: TextStyle(
                  color: AppTheme.textMuted(context),
                  fontSize: 12,
                ),
              ),
              ElevatedButton(
                onPressed: goal.isCompleted ? null : () => _addToGoal(goal),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Add Funds'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showCreateGoalDialog() {
    // TODO: Implement goal creation dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Goal creation coming soon!')),
    );
  }
  
  void _addToGoal(SavingsGoal goal) {
    // TODO: Implement add funds dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add funds coming soon!')),
    );
  }
}

// Summary card widget
class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? prefix;
  final double? change;
  
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.prefix,
    this.change,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${prefix ?? ''}$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          if (change != null) ...[
            const SizedBox(height: 4),
            Text(
              '${change! >= 0 ? '+' : ''}${change!.toStringAsFixed(1)}% vs last period',
              style: TextStyle(
                fontSize: 10,
                color: change! >= 0 ? AppTheme.error : AppTheme.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Period display extension
extension AnalyticsPeriodExtension on AnalyticsPeriod {
  String get displayName {
    switch (this) {
      case AnalyticsPeriod.today:
        return 'Today';
      case AnalyticsPeriod.thisWeek:
        return 'This Week';
      case AnalyticsPeriod.thisMonth:
        return 'This Month';
      case AnalyticsPeriod.last30Days:
        return 'Last 30 Days';
      case AnalyticsPeriod.last90Days:
        return 'Last 90 Days';
      case AnalyticsPeriod.thisYear:
        return 'This Year';
      case AnalyticsPeriod.allTime:
        return 'All Time';
      case AnalyticsPeriod.custom:
        return 'Custom';
    }
  }
}
