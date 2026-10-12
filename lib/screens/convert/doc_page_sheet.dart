import 'package:flutter/material.dart';

import '../../data/doc_paginator.dart';
import '../../data/page_renderer.dart';
import '../../models/doc_text.dart';

/// One page of a converted document, drawn exactly as the paginator measured
/// it.
///
/// The padding and spacing here are not a separate set of numbers that happen
/// to look similar — they come from the same [docIndent], [docSpacingAfter]
/// and [docStyleFor] the paginator used. If the two ever disagreed, the last
/// line of every page would be cut off, so there is only one source for them.
class DocPageSheet extends StatelessWidget {
  const DocPageSheet({
    super.key,
    required this.blocks,
    required this.pageNumber,
    required this.pageCount,
    this.marginPt = 56,
  });

  final List<DocBlock> blocks;
  final int pageNumber;
  final int pageCount;
  final double marginPt;

  @override
  Widget build(BuildContext context) {
    return PaperSheet(
      marginPt: marginPt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final block in blocks)
                    Padding(
                      padding: EdgeInsets.only(
                        left: docIndent(block.style),
                        bottom: docSpacingAfter(block.style),
                      ),
                      child: Text(
                        docDisplayText(block),
                        style: docStyleFor(block.style),
                        // Left-aligned rather than justified: justification
                        // without hyphenation opens rivers of white space, and
                        // Flutter has no hyphenation.
                        textAlign: TextAlign.left,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: docFooterPt,
            child: Center(
              child: Text(
                '$pageNumber of $pageCount',
                style: const TextStyle(
                  fontSize: 8.5,
                  color: Color(0xFF8A8A8A),
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
