import 'package:flutter/material.dart';
import 'package:graphify/graphify.dart';

import '../../core/format/money.dart';

import '../theme/app_colors.dart';

/// A single slice of the donut chart.
class DonutSlice {
  final String label;
  final double value;
  final Color color;

  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// Donut chart rendered with Apache ECharts via graphify (WebView-based).
///
/// Pushes new options through the controller when [slices] change, since
/// GraphifyView only applies `initialOptions` once on page load.
class GraphifyDonutChart extends StatefulWidget {
  final List<DonutSlice> slices;

  const GraphifyDonutChart({super.key, required this.slices});

  @override
  State<GraphifyDonutChart> createState() => _GraphifyDonutChartState();
}

class _GraphifyDonutChartState extends State<GraphifyDonutChart> {
  final _controller = GraphifyController();

  @override
  void didUpdateWidget(GraphifyDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.update(_options());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  Map<String, dynamic> _options() {
    return {
      'backgroundColor': 'transparent',
      'tooltip': {
        'trigger': 'item',
        // El simbolo sale de la moneda configurada, no hardcodeado.
        'formatter': '{b}: ${Money.symbolFor(Money.currencyCode)} {c} ({d}%)',
        'backgroundColor': _hex(AppColors.surfaceDark),
        'borderColor': _hex(AppColors.borderDark),
        'textStyle': {'color': _hex(AppColors.textPrimary)},
      },
      'series': [
        {
          'type': 'pie',
          'radius': ['62%', '85%'],
          'avoidLabelOverlap': false,
          'itemStyle': {
            'borderRadius': 6,
            'borderColor': _hex(AppColors.cardDark),
            'borderWidth': 3,
          },
          'label': {'show': false},
          'emphasis': {
            'scale': true,
            'scaleSize': 6,
          },
          'data': widget.slices
              .map((s) => {
                    'value': double.parse(s.value.toStringAsFixed(2)),
                    'name': s.label,
                    'itemStyle': {'color': _hex(s.color)},
                  })
              .toList(),
        },
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return GraphifyView(
      controller: _controller,
      initialOptions: _options(),
    );
  }
}
