import 'package:flutter/material.dart';
import 'bounce_button.dart';
import 'transitions.dart';

/// 状态屏件(质感工序:每个状态都带风格,不裸奔)。
/// 只管结构+手感,视觉从项目主题(design_feed theme)取。

/// 空状态:插画 + 一句引导 + 行动按钮(禁白屏/"暂无数据")
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.illustration,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Widget illustration; // 项目给:mascot/贴纸图
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PopIn(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 140, child: illustration),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              BounceButton(
                onPressed: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(actionLabel!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误状态:人话 + 可重试(禁裸错误码)
class ErrorRetryState extends StatelessWidget {
  const ErrorRetryState({
    super.key,
    required this.message,
    required this.onRetry,
    this.illustration,
    this.retryLabel = '再试一次',
  });

  final String message; // 人话!"网络开小差了",不是 "request failed: 500"
  final VoidCallback onRetry;
  final Widget? illustration;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      illustration: illustration ?? const Icon(Icons.cloud_off_rounded, size: 96),
      message: message,
      actionLabel: retryLabel,
      onAction: onRetry,
    );
  }
}

/// 结算屏骨架:大标题 + 分数区 + mascot 位 + 主/次按钮(再来一把钩子)
class ResultScaffold extends StatelessWidget {
  const ResultScaffold({
    super.key,
    required this.title,
    required this.scoreArea,
    required this.primaryLabel,
    required this.onPrimary,
    this.mascot,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final Widget scoreArea;
  final Widget? mascot;
  final String primaryLabel;      // "再来一把"——每局必须有钩子
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            PopIn(child: Text(title, style: theme.textTheme.headlineMedium)),
            const SizedBox(height: 12),
            if (mascot != null) SizedBox(height: 120, child: mascot),
            const SizedBox(height: 12),
            PopIn(delay: const Duration(milliseconds: 80), child: scoreArea),
            const Spacer(),
            BounceButton(
              onPressed: onPrimary,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(primaryLabel,
                      style: TextStyle(color: theme.colorScheme.onPrimary,
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 10),
              BounceButton(
                onPressed: onSecondary,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(secondaryLabel!, style: theme.textTheme.titleSmall),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 教学屏骨架:3-5 步卡片轮播(首关 30 秒可懂 —— 可玩性门要点)
class HowToScaffold extends StatelessWidget {
  const HowToScaffold({
    super.key,
    required this.steps,
    required this.onDone,
    this.doneLabel = '开始玩!',
  });

  /// 每步:图(可用 mascot/示意贴纸)+ 一句话
  final List<({Widget visual, String caption})> steps;
  final VoidCallback onDone;
  final String doneLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              itemCount: steps.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: steps[i].visual),
                    const SizedBox(height: 20),
                    Text('${i + 1}. ${steps[i].caption}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: BounceButton(
              onPressed: onDone,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(doneLabel,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
