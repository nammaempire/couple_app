import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Up to six images in a 3-column mosaic, the first one large.
class MemoryRecapCollage extends StatelessWidget {
  const MemoryRecapCollage({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    Widget image(String url) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
    );

    if (urls.length < 3) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: Row(
          children: [
            for (var i = 0; i < urls.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: image(urls[i])),
            ],
          ],
        ),
      );
    }

    final rest = urls.skip(3).toList();
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3 / 2,
          child: Row(
            children: [
              Expanded(flex: 2, child: image(urls[0])),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: image(urls[1])),
                    const SizedBox(height: 4),
                    Expanded(child: image(urls[2])),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 4),
          AspectRatio(
            aspectRatio: 3,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: i < rest.length ? image(rest[i]) : const SizedBox(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
