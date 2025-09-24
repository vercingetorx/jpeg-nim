import std/math

import bitstream, common, dct, format, huffman, quant, zigzag

# Default Huffman tables from Annex K ----------------------------------------

const
  dcLumaCounts = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
  dcChromaCounts = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]

  dcValues = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

  acLumaCounts = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D]
  acChromaCounts = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77]

  acLumaValues = [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
    0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
    0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
    0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
    0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
    0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
    0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
    0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
    0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4,
    0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
    0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
    0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
    0xF9, 0xFA
  ]

  acChromaValues = [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
    0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
    0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
    0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34,
    0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
    0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38,
    0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
    0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
    0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
    0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
    0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
    0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2,
    0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
    0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9,
    0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
    0xF9, 0xFA
  ]

# -----------------------------------------------------------------------------

type
  EncComponent = object
    id: int
    hFactor, vFactor: int
    quantTable: QuantTable
    dcTable: HuffmanTable
    acTable: HuffmanTable
    dcPrev: int
    width, height: int
    plane: seq[int16]

# Utility functions -----------------------------------------------------------

proc toSeq16(data: openArray[int]): seq[int] =
  result = newSeq[int](data.len)
  for i in 0 ..< data.len:
    result[i] = data[i]


proc magnitudeCategory(value: int): int {.inline.} =
  if value == 0:
    return 0
  result = 0
  var v = abs(value)
  while v > 0:
    inc result
    v = v shr 1


proc emitAmplitude(bw: var BitWriter, value, size: int) {.inline.} =
  if size == 0:
    return
  var code = value
  if value < 0:
    code = (1 shl size) + value - 1
  putBits(bw, code, size)


proc planeIndex(width, height, x, y: int): int {.inline.} =
  let clampedX = clamp(x, 0, width - 1)
  let clampedY = clamp(y, 0, height - 1)
  clampedY * width + clampedX


proc extractBlock(comp: EncComponent, blockX, blockY: int, outBlock: var SampleBlock) =
  for y in 0 ..< BlockDim:
    let srcY = blockY * BlockDim + y
    for x in 0 ..< BlockDim:
      let srcX = blockX * BlockDim + x
      let value = int(comp.plane[planeIndex(comp.width, comp.height, srcX, srcY)]) - 128
      outBlock[y * BlockDim + x] = int16(value)


proc encodeBlock(comp: var EncComponent, bw: var BitWriter, blk: CoeffBlock) =
  let dc = int(blk[0])
  let diff = dc - comp.dcPrev
  let size = magnitudeCategory(diff)
  encodeSymbol(bw, comp.dcTable, size)
  emitAmplitude(bw, diff, size)
  comp.dcPrev = dc

  var zeroRun = 0
  for i in 1 ..< BlockSize:
    let coeff = int(blk[i])
    if coeff == 0:
      inc zeroRun
    else:
      while zeroRun >= 16:
        encodeSymbol(bw, comp.acTable, 0xF0)
        zeroRun -= 16
      let acSize = magnitudeCategory(coeff)
      let symbol = (zeroRun shl 4) or acSize
      encodeSymbol(bw, comp.acTable, symbol)
      emitAmplitude(bw, coeff, acSize)
      zeroRun = 0
  if zeroRun > 0:
    encodeSymbol(bw, comp.acTable, 0)


proc subsample420(full: seq[int16], width, height: int): seq[int16] =
  let subW = (width + 1) shr 1
  let subH = (height + 1) shr 1
  result = newSeq[int16](subW * subH)
  for y in 0 ..< subH:
    for x in 0 ..< subW:
      var sum = 0
      var count = 0
      for dy in 0 ..< 2:
        let py = y * 2 + dy
        if py >= height:
          continue
        for dx in 0 ..< 2:
          let px = x * 2 + dx
          if px >= width:
            continue
          sum += int(full[py * width + px])
          inc count
      result[y * subW + x] = int16((sum + count div 2) div max(count, 1))


proc quantToZigzag(table: QuantTable): array[BlockSize, uint8] =
  for i in 0 ..< BlockSize:
    result[i] = uint8(table[int(ZigzagMap[i])])


proc writeMarker(buffer: var seq[byte], marker: uint16) =
  buffer.add(0xFF'u8)
  buffer.add(uint8(marker and 0xFF))


proc writeSegment(buffer: var seq[byte], marker: uint16, payload: seq[byte]) =
  writeMarker(buffer, marker)
  let length = payload.len + 2
  buffer.add(uint8((length shr 8) and 0xFF))
  buffer.add(uint8(length and 0xFF))
  buffer.add(payload)


proc buildDefaultTables(): tuple[dcLuma, dcChroma, acLuma, acChroma: HuffmanTable] =
  result.dcLuma = buildHuffmanTable(toSeq16(dcLumaCounts), dcValues)
  result.dcChroma = buildHuffmanTable(toSeq16(dcChromaCounts), dcValues)
  result.acLuma = buildHuffmanTable(toSeq16(acLumaCounts), acLumaValues)
  result.acChroma = buildHuffmanTable(toSeq16(acChromaCounts), acChromaValues)


proc emitScan(components: var array[3, EncComponent], width, height: int): seq[byte] =
  var bw = initBitWriter()
  let mcuWidth = 16
  let mcuHeight = 16
  let mcusX = (width + mcuWidth - 1) div mcuWidth
  let mcusY = (height + mcuHeight - 1) div mcuHeight
  var blockBuf: SampleBlock

  for comp in components.mitems:
    comp.dcPrev = 0

  for my in 0 ..< mcusY:
    for mx in 0 ..< mcusX:
      for compIndex, comp in components.mpairs:
        let h = comp.hFactor
        let v = comp.vFactor
        for by in 0 ..< v:
          for bx in 0 ..< h:
            extractBlock(comp, mx * h + bx, my * v + by, blockBuf)
            let freq = forwardDCT(blockBuf)
            let quant = quantizeBlock(freq, comp.quantTable)
            let zig = zigzag(quant)
            encodeBlock(comp, bw, zig)
  flushBits(bw)
  bw.buffer


proc writeDQTSegment(luma, chroma: QuantTable): seq[byte] =
  var payload: seq[byte]
  payload.add(uint8(0))
  let lumaZig = quantToZigzag(luma)
  for v in lumaZig:
    payload.add(uint8(v))
  payload.add(uint8(1))
  let chromaZig = quantToZigzag(chroma)
  for v in chromaZig:
    payload.add(uint8(v))
  payload


proc writeDHTSegment(tableClass: int, tableId: int, counts: array[16, int], values: openArray[int]): seq[byte] =
  var payload: seq[byte]
  payload.add(uint8((tableClass shl 4) or tableId))
  for count in counts:
    payload.add(uint8(count and 0xFF))
  for v in values:
    payload.add(uint8(v and 0xFF))
  payload


proc encodeJpeg*(image: Image, quality: int = 90): seq[byte] =
  let q = clamp(quality, 1, 100)
  let scaledLuma = scaleQuantTable(defaultLuminanceQTable, q)
  let scaledChroma = scaleQuantTable(defaultChrominanceQTable, q)
  let tables = buildDefaultTables()

  # Convert image to YCbCr and subsample
  let width = image.width
  let height = image.height
  var yFull = newSeq[int16](width * height)
  var cbFull = newSeq[int16](width * height)
  var crFull = newSeq[int16](width * height)

  for y in 0 ..< height:
    for x in 0 ..< width:
      let idx = (y * width + x) * 3
      let r = image.data[idx]
      let g = image.data[idx + 1]
      let b = image.data[idx + 2]
      let yc = rgbToYCbCr(r, g, b)
      let pos = y * width + x
      yFull[pos] = int16(yc.y)
      cbFull[pos] = int16(yc.cb)
      crFull[pos] = int16(yc.cr)

  var components: array[3, EncComponent]
  components[0] = EncComponent(
    id: 1,
    hFactor: 2,
    vFactor: 2,
    quantTable: scaledLuma,
    dcTable: tables.dcLuma,
    acTable: tables.acLuma,
    width: width,
    height: height,
    plane: yFull
  )

  let subWidth = (width + 1) shr 1
  let subHeight = (height + 1) shr 1

  components[1] = EncComponent(
    id: 2,
    hFactor: 1,
    vFactor: 1,
    quantTable: scaledChroma,
    dcTable: tables.dcChroma,
    acTable: tables.acChroma,
    width: subWidth,
    height: subHeight,
    plane: subsample420(cbFull, width, height)
  )

  components[2] = EncComponent(
    id: 3,
    hFactor: 1,
    vFactor: 1,
    quantTable: scaledChroma,
    dcTable: tables.dcChroma,
    acTable: tables.acChroma,
    width: subWidth,
    height: subHeight,
    plane: subsample420(crFull, width, height)
  )

  var output: seq[byte]
  writeMarker(output, 0xFFD8'u16)

  # APP0 JFIF
  var app0: seq[byte]
  app0.add(@[byte('J'), byte('F'), byte('I'), byte('F'), 0'u8])
  app0.add(@[0x01'u8, 0x02'u8, 0x00'u8])
  app0.add(@[0x00'u8, 0x01'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8])
  writeSegment(output, 0xFFE0'u16, app0)

  # DQT
  writeSegment(output, 0xFFDB'u16, writeDQTSegment(scaledLuma, scaledChroma))

  # SOF0
  var sof0: seq[byte]
  sof0.add(0x08'u8)
  sof0.add(uint8((height shr 8) and 0xFF))
  sof0.add(uint8(height and 0xFF))
  sof0.add(uint8((width shr 8) and 0xFF))
  sof0.add(uint8(width and 0xFF))
  sof0.add(0x03'u8)
  sof0.add(0x01'u8)
  sof0.add(0x22'u8)
  sof0.add(0x00'u8)
  sof0.add(0x02'u8)
  sof0.add(0x11'u8)
  sof0.add(0x01'u8)
  sof0.add(0x03'u8)
  sof0.add(0x11'u8)
  sof0.add(0x01'u8)
  writeSegment(output, 0xFFC0'u16, sof0)

  # DHT (luma DC + AC)
  writeSegment(output, 0xFFC4'u16, writeDHTSegment(0, 0, dcLumaCounts, dcValues) &
                                       writeDHTSegment(1, 0, acLumaCounts, acLumaValues))
  # DHT (chroma DC + AC)
  writeSegment(output, 0xFFC4'u16, writeDHTSegment(0, 1, dcChromaCounts, dcValues) &
                                       writeDHTSegment(1, 1, acChromaCounts, acChromaValues))

  # SOS
  var sos: seq[byte]
  sos.add(0x03'u8)
  sos.add(0x01'u8)
  sos.add(0x00'u8)
  sos.add(0x02'u8)
  sos.add(0x11'u8)
  sos.add(0x03'u8)
  sos.add(0x11'u8)
  sos.add(0x00'u8)
  sos.add(0x3F'u8)
  sos.add(0x00'u8)
  writeSegment(output, 0xFFDA'u16, sos)

  let entropy = emitScan(components, width, height)
  output.add(entropy)

  writeMarker(output, 0xFFD9'u16)
  output
