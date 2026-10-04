import 'package:flutter/material.dart';

/// A scalable, bundled illustration: rider in a red coat on a white hobby horse.
class LajkonikAvatar extends StatelessWidget {
  const LajkonikAvatar({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Lajkonik',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LajkonikPainter()),
    ),
  );
}

class _LajkonikPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const red = Color(0xFFBD3C3B);
    const gold = Color(0xFFF2C65E);
    const dark = Color(0xFF293D31);
    final brush = Paint()..isAntiAlias = true;
    void oval(Rect rect, Color color) =>
        canvas.drawOval(rect, brush..color = color);
    void path(Path path, Color color) =>
        canvas.drawPath(path, brush..color = color);
    void line(Offset a, Offset b, Color color, double width) => canvas.drawLine(
      a,
      b,
      brush
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );

    oval(const Rect.fromLTWH(7, 86, 83, 9), dark.withValues(alpha: .16));
    // Rider's boots and coat.
    line(const Offset(40, 77), const Offset(35, 88), dark, 8);
    line(const Offset(61, 77), const Offset(65, 88), dark, 8);
    path(
      Path()
        ..moveTo(39, 40)
        ..quadraticBezierTo(26, 45, 27, 69)
        ..lineTo(70, 69)
        ..quadraticBezierTo(71, 44, 59, 40)
        ..close(),
      red,
    );
    line(const Offset(48, 44), const Offset(48, 65), gold, 3);
    line(const Offset(31, 61), const Offset(65, 61), gold, 5);
    // White horse, curved neck and red bridle.
    oval(const Rect.fromLTWH(14, 61, 66, 22), const Color(0xFFFFF7DE));
    path(
      Path()
        ..moveTo(65, 73)
        ..lineTo(67, 51)
        ..lineTo(76, 41)
        ..lineTo(78, 31)
        ..lineTo(84, 40)
        ..lineTo(91, 47)
        ..quadraticBezierTo(98, 54, 88, 57)
        ..lineTo(81, 55)
        ..lineTo(81, 74)
        ..close(),
      Colors.white,
    );
    line(const Offset(72, 44), const Offset(69, 64), dark, 5);
    line(const Offset(82, 44), const Offset(86, 56), red, 2.5);
    line(const Offset(85, 54), const Offset(55, 55), red, 2);
    oval(const Rect.fromLTWH(83, 46, 3, 3), dark);
    line(const Offset(17, 67), const Offset(9, 62), dark, 4);
    oval(const Rect.fromLTWH(41, 63, 20, 16), red);
    // Hand and ceremonial staff.
    line(const Offset(27, 50), const Offset(20, 54), red, 9);
    line(const Offset(19, 36), const Offset(19, 66), gold, 3);
    oval(const Rect.fromLTWH(14, 26, 10, 10), gold);
    oval(const Rect.fromLTWH(15, 49, 8, 8), const Color(0xFFF3BF8B));
    oval(const Rect.fromLTWH(56, 50, 8, 8), const Color(0xFFF3BF8B));
    // Face, dark beard and red-and-gold headdress.
    oval(const Rect.fromLTWH(37, 24, 25, 24), const Color(0xFFF3BF8B));
    path(
      Path()
        ..moveTo(37, 36)
        ..quadraticBezierTo(49, 44, 62, 35)
        ..quadraticBezierTo(60, 50, 49, 51)
        ..quadraticBezierTo(38, 49, 37, 36)
        ..close(),
      dark,
    );
    oval(const Rect.fromLTWH(42, 31, 2.5, 2.5), dark);
    oval(const Rect.fromLTWH(54, 31, 2.5, 2.5), dark);
    path(
      Path()
        ..moveTo(35, 27)
        ..lineTo(38, 15)
        ..quadraticBezierTo(47, 4, 57, 15)
        ..lineTo(65, 27)
        ..close(),
      red,
    );
    line(const Offset(36, 25), const Offset(63, 25), gold, 5);
    oval(const Rect.fromLTWH(47, 13, 6, 8), gold);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
