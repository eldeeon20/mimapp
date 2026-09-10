import 'package:flutter/material.dart';

/// Candado central con pulso al tocar: se achica y rebota mientras abre
/// el menú radial. El toque vive SOLO en el medallón (105px).
class CandadoCentral extends StatefulWidget {
  final VoidCallback onTap;
  const CandadoCentral({super.key, required this.onTap});

  @override
  State<CandadoCentral> createState() => _CandadoCentralState();
}

class _CandadoCentralState extends State<CandadoCentral>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _esc;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _esc = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.84)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.84, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tocar() {
    _c.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 340,
        height: 330,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.blueAccent.withValues(alpha: .12),
                    blurRadius: 100,
                    spreadRadius: 30,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _tocar,
              behavior: HitTestBehavior.opaque,
              child: ScaleTransition(
                scale: _esc,
                child: Container(
                  width: 105,
                  height: 105,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF111A46),
                    border: Border.all(
                      color: Colors.deepPurpleAccent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurpleAccent
                            .withValues(alpha: .45),
                        blurRadius: 35,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 58,
                    color: Color(0xFFB57CFF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
