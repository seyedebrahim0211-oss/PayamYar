import 'dart:io';
import 'package:flutter/material.dart';
import '../chat_personalization.dart';

class FramedChatImage extends StatelessWidget {
  final String path;
  final ImageFrame frame;
  final int pixels;
  final Widget? fallback;
  const FramedChatImage(this.path, this.frame, {super.key, this.pixels = 1600, this.fallback});

  @override
  Widget build(BuildContext context) => ClipRect(child: FractionalTranslation(
    translation: Offset(frame.x, frame.y),
    child: Transform.scale(scale: frame.zoom, child: FittedBox(fit: BoxFit.cover,
      child: Image(image: ResizeImage(FileImage(File(path)), width: pixels,
        height: pixels, policy: ResizeImagePolicy.fit),
        errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink())))));
}

class ChatFrameEditor extends StatefulWidget {
  final String path;
  final ImageFrame initial;
  final double aspect;
  final bool wallpaper;
  const ChatFrameEditor({super.key, required this.path, required this.initial,
    required this.aspect, required this.wallpaper});
  @override
  State<ChatFrameEditor> createState() => _ChatFrameEditorState();
}

class _ChatFrameEditorState extends State<ChatFrameEditor> {
  late ImageFrame frame = widget.initial;
  late ImageFrame start;
  late Offset anchor;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.wallpaper ? 'قاب پس‌زمینه' : 'قاب عکس مخاطب'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, frame), child: const Text('ذخیره'))]),
    body: SafeArea(child: Column(children: [
      Expanded(child: Center(child: AspectRatio(aspectRatio: widget.aspect,
        child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          Offset unit(Offset point) => Offset(point.dx / size.width - .5, point.dy / size.height - .5);
          return ClipRRect(borderRadius: BorderRadius.circular(widget.wallpaper ? 0 : size.width * .34),
            child: GestureDetector(behavior: HitTestBehavior.opaque,
              onScaleStart: (d) { start = frame; anchor = unit(d.localFocalPoint); },
              onScaleUpdate: (d) {
                final zoom = (start.zoom * d.scale).clamp(.25, 5.0).toDouble();
                final pos = unit(d.localFocalPoint) -
                    (anchor - Offset(start.x, start.y)) * (zoom / start.zoom);
                setState(() => frame = ImageFrame(zoom, pos.dx.clamp(-.9, .9).toDouble(),
                    pos.dy.clamp(-.9, .9).toDouble()));
              },
              child: ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer,
                child: FramedChatImage(widget.path, frame))));
        })))),
      const Padding(padding: EdgeInsets.all(10),
        child: Text('با دو انگشت اندازه را تغییر دهید و عکس را جابه‌جا کنید.')),
      Row(children: [
        IconButton(tooltip: 'بازنشانی قاب', icon: const Icon(Icons.restart_alt),
          onPressed: () => setState(() => frame = const ImageFrame())),
        Expanded(child: Slider(min: .25, max: 5, value: frame.zoom,
          onChanged: (v) => setState(() => frame = ImageFrame(v, frame.x, frame.y)))),
      ]),
    ])));
}
