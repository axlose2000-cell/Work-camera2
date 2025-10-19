import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:io';

/// 여러 이미지를 슬라이드로 볼 수 있는 통합 이미지 뷰어
/// - images: File 리스트(이미지 파일들)
/// - initialIndex: 처음 보여줄 이미지 인덱스
class ImageViewer extends StatefulWidget {
  final List<File> images; // 전체 이미지 파일 리스트
  final int initialIndex; // 시작 인덱스

  const ImageViewer({super.key, required this.images, this.initialIndex = 0});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late PageController _pageController; // 슬라이드(페이지) 컨트롤러
  late int _currentIndex; // 현재 보고 있는 이미지 인덱스
  late PhotoViewController _photoController; // 각 페이지별 확대 컨트롤러

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex; // 시작 인덱스 설정
    _pageController = PageController(initialPage: _currentIndex); // PageView 컨트롤러 초기화
    _photoController = PhotoViewController(); // 첫 컨트롤러 생성
  }

  @override
  void dispose() {
    _pageController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  void _onPageChanged(int idx) {
    setState(() {
      _currentIndex = idx;
      _photoController.dispose();
      _photoController = PhotoViewController(); // 페이지 변경 시 컨트롤러 새로 생성
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 AppBar에 현재 인덱스/전체 이미지 수 표시
      appBar: AppBar(
        title: Text('${_currentIndex + 1} / ${widget.images.length}'),
      ),
      // PageView로 이미지 슬라이드
      body: PageView.builder(
        controller: _pageController, // 페이지 이동 컨트롤러
        itemCount: widget.images.length, // 전체 이미지 개수
        onPageChanged: _onPageChanged, // 페이지 변경 시 컨트롤러 리셋
        itemBuilder: (context, idx) {
          return GestureDetector(
            onDoubleTap: () {
              final currentScale = _photoController.scale ?? 1.0;
              if (currentScale == 1.0) {
                _photoController.scale = 3.0; // 바로 3배 확대
              } else {
                _photoController.scale = 1.0; // 다시 원래 크기
              }
            },
            child: PhotoView(
              controller: _photoController,
              imageProvider: FileImage(widget.images[idx]),
              minScale: PhotoViewComputedScale.contained, // 화면에 맞게 기본 표시
              maxScale: PhotoViewComputedScale.covered * 3, // 최대 3배 확대
              initialScale: PhotoViewComputedScale.contained, // 시작은 화면 맞춤
              backgroundDecoration: const BoxDecoration(
                color: Colors.black, // 배경색 (갤러리 느낌)
              ),
            ),
          );
        },
      ),
    );
  }
}
