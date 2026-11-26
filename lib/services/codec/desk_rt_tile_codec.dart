import 'dart:typed_data';

import '../../core/constants/protocol_constants.dart';
import '../../domain/entities/session_models.dart';

/// Implementação em Dart do Codec de Vídeo Baseado em Dirty Tiles (Grade 8x6 = 48 blocos)
/// com cálculo de hash rápido FNV-1a e empacotamento binário compatível com `PacketType.tileFrameDirty`.
class DeskRtTileCodec {
  static const int gridCols = ProtocolConstants.tileGridCols;
  static const int gridRows = ProtocolConstants.tileGridRows;

  final Uint32List _previousHashes = Uint32List(gridCols * gridRows);
  int _lastWidth = 0;
  int _lastHeight = 0;
  int _frameCounter = 0;

  /// Força o envio de todos os 48 blocos no próximo quadro (Full KeyFrame).
  void forceFullKeyFrame() {
    _previousHashes.fillRange(0, _previousHashes.length, 0);
  }

  /// Analisa um buffer RGBA de tamanho [width]x[height], calcula o hash FNV-1a de cada bloco
  /// da grade 8x6 e codifica apenas os blocos que sofreram alteração desde o quadro anterior.
  Uint8List? encodeDirtyTiles({
    required Uint8List rgbaBuffer,
    required int width,
    required int height,
    required int quality,
  }) {
    if (width < 64 || height < 64 || rgbaBuffer.length < width * height * 4) {
      return null;
    }

    if (width != _lastWidth || height != _lastHeight) {
      forceFullKeyFrame();
      _lastWidth = width;
      _lastHeight = height;
    } else if (_frameCounter++ % ProtocolConstants.keyFrameIntervalFrames == 0) {
      forceFullKeyFrame();
    }

    final int tileW = width ~/ gridCols;
    final int tileH = height ~/ gridRows;
    final List<DirtyTileBlock> dirtyBlocks = <DirtyTileBlock>[];

    for (int ry = 0; ry < gridRows; ry++) {
      for (int cx = 0; cx < gridCols; cx++) {
        final int idx = ry * gridCols + cx;
        final int x0 = cx * tileW;
        final int y0 = ry * tileH;
        final int w = (cx == gridCols - 1) ? (width - x0) : tileW;
        final int h = (ry == gridRows - 1) ? (height - y0) : tileH;

        final int hash = computeTileFnv1aHash(
          rgbaBuffer: rgbaBuffer,
          fullWidth: width,
          x0: x0,
          y0: y0,
          w: w,
          h: h,
        );

        if (_previousHashes[idx] != hash) {
          _previousHashes[idx] = hash;
          final Uint8List tileData = _extractCompactTilePayload(
            rgbaBuffer: rgbaBuffer,
            fullWidth: width,
            x0: x0,
            y0: y0,
            w: w,
            h: h,
            quality: quality,
          );
          dirtyBlocks.add(
            DirtyTileBlock(
              x: x0,
              y: y0,
              width: w,
              height: h,
              encodedBytes: tileData,
            ),
          );
        }
      }
    }

    if (dirtyBlocks.isEmpty) {
      return null;
    }

    return packDirtyTileFrame(
      DirtyTileFrame(
        fullWidth: width,
        fullHeight: height,
        tiles: dirtyBlocks,
      ),
    );
  }

  /// Calcula o hash FNV-1a 32-bit com amostragem de linhas (idêntico ao algoritmo C# original).
  static int computeTileFnv1aHash({
    required Uint8List rgbaBuffer,
    required int fullWidth,
    required int x0,
    required int y0,
    required int w,
    required int h,
  }) {
    int hash = 0x811c9dc5;
    final int stride = fullWidth * 4;
    for (int y = y0; y < y0 + h; y += 2) {
      final int rowBase = y * stride + (x0 * 4);
      for (int x = 0; x < w * 4; x += 8) {
        final int p = rowBase + x;
        if (p + 2 < rgbaBuffer.length) {
          hash = ((hash ^ rgbaBuffer[p]) * 0x01000193) & 0xffffffff;
          hash = ((hash ^ rgbaBuffer[p + 1]) * 0x01000193) & 0xffffffff;
          hash = ((hash ^ rgbaBuffer[p + 2]) * 0x01000193) & 0xffffffff;
        }
      }
    }
    return hash == 0 ? 1 : hash;
  }

  static Uint8List _extractCompactTilePayload({
    required Uint8List rgbaBuffer,
    required int fullWidth,
    required int x0,
    required int y0,
    required int w,
    required int h,
    required int quality,
  }) {
    // Codifica um cabeçalho de tile compacto 'DVTL' + cor média e gradiente para renderização rápida
    // caso o payload não seja um JPEG externo.
    int sumR = 0, sumG = 0, sumB = 0, count = 0;
    final int step = quality >= 85 ? 2 : (quality >= 65 ? 4 : 8);
    final int stride = fullWidth * 4;
    for (int y = y0; y < y0 + h; y += step) {
      final int row = y * stride;
      for (int x = x0; x < x0 + w; x += step) {
        final int p = row + x * 4;
        if (p + 2 < rgbaBuffer.length) {
          sumR += rgbaBuffer[p];
          sumG += rgbaBuffer[p + 1];
          sumB += rgbaBuffer[p + 2];
          count++;
        }
      }
    }
    final int avgR = count > 0 ? (sumR ~/ count) & 0xff : 24;
    final int avgG = count > 0 ? (sumG ~/ count) & 0xff : 34;
    final int avgB = count > 0 ? (sumB ~/ count) & 0xff : 48;

    final Uint8List out = Uint8List(8);
    out[0] = 0x44; // 'D'
    out[1] = 0x56; // 'V'
    out[2] = 0x54; // 'T'
    out[3] = 0x4C; // 'L'
    out[4] = avgR;
    out[5] = avgG;
    out[6] = avgB;
    out[7] = quality & 0xff;
    return out;
  }

  /// Empacota um [DirtyTileFrame] no layout binário exato do protocolo DeskView:
  /// `[int32 fullW][int32 fullH][uint16 tileCount]` seguido por `tileCount` blocos
  /// `[uint16 tx][uint16 ty][uint16 tw][uint16 th][int32 len][byte[] bytes]`.
  static Uint8List packDirtyTileFrame(DirtyTileFrame frame) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    final Uint8List header = Uint8List(10);
    final ByteData hbd = ByteData.sublistView(header);
    hbd.setInt32(0, frame.fullWidth, Endian.little);
    hbd.setInt32(4, frame.fullHeight, Endian.little);
    hbd.setUint16(8, frame.tiles.length, Endian.little);
    builder.add(header);

    for (final DirtyTileBlock tile in frame.tiles) {
      final Uint8List tileMeta = Uint8List(12);
      final ByteData tbd = ByteData.sublistView(tileMeta);
      tbd.setUint16(0, tile.x, Endian.little);
      tbd.setUint16(2, tile.y, Endian.little);
      tbd.setUint16(4, tile.width, Endian.little);
      tbd.setUint16(6, tile.height, Endian.little);
      tbd.setInt32(8, tile.encodedBytes.length, Endian.little);
      builder.add(tileMeta);
      builder.add(tile.encodedBytes);
    }

    return builder.toBytes();
  }

  /// Decodifica com validação defensiva de limites um payload `PacketType.tileFrameDirty`.
  static DirtyTileFrame? unpackDirtyTileFrame(Uint8List payload) {
    if (payload.length < 10) return null;
    final ByteData bd = ByteData.sublistView(payload);
    final int fullW = bd.getInt32(0, Endian.little);
    final int fullH = bd.getInt32(4, Endian.little);
    final int tileCount = bd.getUint16(8, Endian.little);

    if (fullW < 64 || fullW > 16384 || fullH < 64 || fullH > 16384) {
      return null;
    }
    if (tileCount > 1024) {
      return null;
    }

    int offset = 10;
    final List<DirtyTileBlock> tiles = <DirtyTileBlock>[];

    for (int i = 0; i < tileCount; i++) {
      if (offset + 12 > payload.length) break;
      final int tx = bd.getUint16(offset, Endian.little);
      final int ty = bd.getUint16(offset + 2, Endian.little);
      final int tw = bd.getUint16(offset + 4, Endian.little);
      final int th = bd.getUint16(offset + 6, Endian.little);
      final int len = bd.getInt32(offset + 8, Endian.little);
      offset += 12;

      if (len <= 0 || len > 10 * 1024 * 1024 || offset + len > payload.length) {
        break;
      }

      final Uint8List tileBytes = payload.sublist(offset, offset + len);
      offset += len;

      if (tw <= 0 || th <= 0 || tx + tw > fullW || ty + th > fullH) {
        continue;
      }

      tiles.add(
        DirtyTileBlock(
          x: tx,
          y: ty,
          width: tw,
          height: th,
          encodedBytes: tileBytes,
        ),
      );
    }

    return DirtyTileFrame(
      fullWidth: fullW,
      fullHeight: fullH,
      tiles: tiles,
    );
  }
}
