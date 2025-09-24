import std/[math, os]

import common, bitstream, dct, format, huffman, quant, zigzag

const
  soiMarker = 0xFFD8'u16
  eoiMarker = 0xFFD9'u16
  sof0Marker = 0xFFC0'u16
  dhtMarker = 0xFFC4'u16
  dqtMarker = 0xFFDB'u16
  driMarker = 0xFFDD'u16
  sosMarker = 0xFFDA'u16
  rstMarkerStart = 0xFFD0'u16
  rstMarkerEnd = 0xFFD7'u16
  rstMarkerStartByte = uint8(rstMarkerStart and 0x00FF'u16)
  rstMarkerEndByte = uint8(rstMarkerEnd and 0x00FF'u16)

# Decoder state ---------------------------------------------------------------

type
  DecoderComponent = object
    spec: ComponentSpec
    width, height: int
    plane: seq[int16]
    dcPrev: int

  DecoderState = object
    width, height: int
    components: seq[DecoderComponent]
    quantTables: array[4, QuantTable]
    quantValid: array[4, bool]
    huffmanTables: array[2, array[4, HuffmanTable]]
    huffValid: array[2, array[4, bool]]
    restartInterval: int
    maxH, maxV: int
    scanOrder: seq[int]

# -----------------------------------------------------------------------------

proc readUint16(data: seq[byte], pos: var int): int =
  if pos + 1 >= data.len:
    raise newException(ValueError, "Unexpected end of file")
  let value = (int(data[pos]) shl 8) or int(data[pos + 1])
  pos += 2
  value


proc readMarker(data: seq[byte], pos: var int): uint16 =
  while pos < data.len and data[pos] != 0xFF'u8:
    inc pos
  if pos >= data.len:
    raise newException(ValueError, "Marker not found")
  while pos < data.len and data[pos] == 0xFF'u8:
    inc pos
  if pos >= data.len:
    raise newException(ValueError, "Marker missing code byte")
  let marker = 0xFF00'u16 or uint16(data[pos])
  inc pos
  marker


proc clampBlockValue(value: int): int16 {.inline.} =
  int16(clamp(value, 0, 255))


proc ensureQuant(state: DecoderState, id: int) =
  if not state.quantValid[id]:
    raise newException(ValueError, "Quantization table " & $id & " missing")


proc ensureHuffman(state: DecoderState, classId, tableId: int) =
  if not state.huffValid[classId][tableId]:
    raise newException(ValueError, "Huffman table missing: class=" & $classId & " id=" & $tableId)


proc parseDQT(state: var DecoderState, segment: openArray[byte]) =
  var idx = 0
  while idx < segment.len:
    let info = segment[idx]; inc idx
    let precision = int(info shr 4)
    let tableId = int(info and 0x0F)
    if tableId >= state.quantTables.len:
      raise newException(ValueError, "Quantization table id out of range")
    if precision != 0:
      raise newException(ValueError, "Only 8-bit quantization tables supported")
    if idx + BlockSize > segment.len:
      raise newException(ValueError, "Quantization table truncated")
    var zig: array[BlockSize, int16]
    for i in 0 ..< BlockSize:
      zig[i] = int16(segment[idx + i])
    let ordered = deZigzag(zig)
    for i in 0 ..< BlockSize:
      state.quantTables[tableId][i] = uint16(ordered[i])
    state.quantValid[tableId] = true
    idx += BlockSize


proc parseDHT(state: var DecoderState, segment: openArray[byte]) =
  var idx = 0
  while idx < segment.len:
    if idx >= segment.len:
      raise newException(ValueError, "Invalid Huffman table segment")
    let info = segment[idx]; inc idx
    let tableClass = int(info shr 4)
    let tableId = int(info and 0x0F)
    if tableClass notin {0, 1} or tableId >= 4:
      raise newException(ValueError, "Invalid Huffman table spec")

    if idx + 16 > segment.len:
      raise newException(ValueError, "Huffman code lengths truncated")
    var codeLengths = newSeq[int](16)
    for i in 0 ..< 16:
      codeLengths[i] = int(segment[idx]); inc idx

    var totalValues = 0
    for lenCount in codeLengths:
      totalValues += lenCount
    if idx + totalValues > segment.len:
      raise newException(ValueError, "Huffman values truncated")
    var values = newSeq[int](totalValues)
    for i in 0 ..< totalValues:
      values[i] = int(segment[idx + i])
    idx += totalValues

    state.huffmanTables[tableClass][tableId] = buildHuffmanTable(codeLengths, values)
    state.huffValid[tableClass][tableId] = true


proc parseSOF0(state: var DecoderState, segment: openArray[byte]) =
  if segment.len < 6:
    raise newException(ValueError, "SOF0 segment too short")
  if segment[0] != 8'u8:
    raise newException(ValueError, "Only 8-bit precision supported")
  let height = (int(segment[1]) shl 8) or int(segment[2])
  let width = (int(segment[3]) shl 8) or int(segment[4])
  let components = int(segment[5])
  if components notin {1, 3}:
    raise newException(ValueError, "Unsupported component count: " & $components)
  if segment.len < 6 + components * 3:
    raise newException(ValueError, "SOF0 component data truncated")

  state.width = width
  state.height = height
  state.components.setLen(components)
  state.maxH = 0
  state.maxV = 0

  var offset = 6
  for i in 0 ..< components:
    var comp = DecoderComponent()
    comp.spec.id = segment[offset]; inc offset
    let sampling = segment[offset]; inc offset
    comp.spec.hFactor = uint8(sampling shr 4)
    comp.spec.vFactor = uint8(sampling and 0x0F)
    comp.spec.quantId = segment[offset]; inc offset
    comp.dcPrev = 0
    state.maxH = max(state.maxH, int(comp.spec.hFactor))
    state.maxV = max(state.maxV, int(comp.spec.vFactor))
    state.components[i] = comp


proc finalizeComponents(state: var DecoderState) =
  for comp in state.components.mitems:
    ensureQuant(state, int(comp.spec.quantId))
    comp.width = (state.width * int(comp.spec.hFactor) + state.maxH - 1) div state.maxH
    comp.height = (state.height * int(comp.spec.vFactor) + state.maxV - 1) div state.maxV
    comp.plane = newSeq[int16](comp.width * comp.height)


proc parseSOS(state: var DecoderState, segment: openArray[byte]) =
  if segment.len < 3:
    raise newException(ValueError, "SOS segment too short")
  let count = int(segment[0])
  if count != state.components.len:
    raise newException(ValueError, "Only full-component scans supported")
  if segment.len < 1 + count * 2 + 3:
    raise newException(ValueError, "SOS selector data truncated")

  state.scanOrder.setLen(count)
  var offset = 1
  for i in 0 ..< count:
    let compId = segment[offset]; inc offset
    let tableInfo = segment[offset]; inc offset
    var found = false
    for idx, comp in state.components.mpairs:
      if comp.spec.id == compId:
        comp.spec.dcTableId = uint8(tableInfo shr 4)
        comp.spec.acTableId = uint8(tableInfo and 0x0F)
        ensureHuffman(state, 0, int(comp.spec.dcTableId))
        ensureHuffman(state, 1, int(comp.spec.acTableId))
        state.scanOrder[i] = idx
        found = true
        break
    if not found:
      raise newException(ValueError, "SOS references unknown component")

  # Skip Ss, Se, AhAl bytes (baseline values expected: 0, 63, 0)
  # They are not used in baseline decoding.


proc parseDRI(state: var DecoderState, segment: openArray[byte]) =
  if segment.len < 2:
    raise newException(ValueError, "DRI segment too short")
  state.restartInterval = (int(segment[0]) shl 8) or int(segment[1])

# Entropy decoding ------------------------------------------------------------

proc receive(br: var BitReader, length: int): int =
  if length == 0:
    return 0
  getBits(br, length)


proc extend(value, length: int): int {.inline.} =
  if length == 0:
    return 0
  let vt = 1 shl (length - 1)
  if value < vt:
    value - ((1 shl length) - 1)
  else:
    value


proc decodeBlock(state: var DecoderState, br: var BitReader, compIndex: int, zz: var array[BlockSize, int16]) =
  var comp = addr state.components[compIndex]
  let dcTableId = int(comp[].spec.dcTableId)
  let acTableId = int(comp[].spec.acTableId)
  let dcSymbol = decodeSymbol(br, state.huffmanTables[0][dcTableId])
  if dcSymbol < 0:
    raise newException(ValueError, "Failed to decode DC coefficient")
  let dcBits = receive(br, dcSymbol)
  if dcBits < 0:
    raise newException(ValueError, "Invalid DC bits")
  let dcValue = extend(dcBits, dcSymbol)
  comp[].dcPrev += dcValue
  zz[0] = int16(comp[].dcPrev)

  var k = 1
  while k < BlockSize:
    let symbol = decodeSymbol(br, state.huffmanTables[1][acTableId])
    if symbol < 0:
      raise newException(ValueError, "Failed to decode AC coefficient")
    if symbol == 0:
      while k < BlockSize:
        zz[k] = 0
        inc k
      break
    if symbol == 0xF0:
      for _ in 0 ..< 16:
        if k < BlockSize:
          zz[k] = 0
          inc k
      continue
    let run = symbol shr 4
    let size = symbol and 0x0F
    for _ in 0 ..< run:
      if k >= BlockSize:
        break
      zz[k] = 0
      inc k
    if k >= BlockSize:
      break
    let acBits = receive(br, size)
    if acBits < 0:
      raise newException(ValueError, "Invalid AC bits")
    let coeff = extend(acBits, size)
    zz[k] = int16(coeff)
    inc k
  while k < BlockSize:
    zz[k] = 0
    inc k


proc storeBlock(comp: var DecoderComponent, blk: SampleBlock, blockX, blockY: int) =
  let baseX = blockX * BlockDim
  let baseY = blockY * BlockDim
  for y in 0 ..< BlockDim:
    let destY = baseY + y
    if destY >= comp.height:
      break
    if baseX >= comp.width:
      continue
    var offset = destY * comp.width + baseX
    for x in 0 ..< BlockDim:
      let destX = baseX + x
      if destX >= comp.width:
        break
      let value = int(blk[y * BlockDim + x]) + 128
      comp.plane[offset + x] = clampBlockValue(value)


proc decodeScan(state: var DecoderState, data: seq[byte]) =
  finalizeComponents(state)
  var br = initBitReader(data)
  let mcuWidth = state.maxH * BlockDim
  let mcuHeight = state.maxV * BlockDim
  let mcusX = (state.width + mcuWidth - 1) div mcuWidth
  let mcusY = (state.height + mcuHeight - 1) div mcuHeight
  var mcuCounter = 0
  var zz: array[BlockSize, int16]

  for my in 0 ..< mcusY:
    for mx in 0 ..< mcusX:
      for compIndex in state.scanOrder:
        var comp = addr state.components[compIndex]
        let h = int(comp[].spec.hFactor)
        let v = int(comp[].spec.vFactor)
        for blockY in 0 ..< v:
          for blockX in 0 ..< h:
            decodeBlock(state, br, compIndex, zz)
            let natural = deZigzag(zz)
            let dequant = dequantizeBlock(natural, state.quantTables[int(comp[].spec.quantId)])
            let spatial = inverseDCT(dequant)
            let destX = mx * h + blockX
            let destY = my * v + blockY
            storeBlock(comp[], spatial, destX, destY)
      inc mcuCounter
      if state.restartInterval > 0 and (mcuCounter mod state.restartInterval) == 0:
        discardBits(br)
        for comp in state.components.mitems:
          comp.dcPrev = 0


proc assembleImage(state: DecoderState): Image =
  var img = initImage(state.width, state.height)
  if state.components.len == 1:
    let comp = state.components[0]
    for y in 0 ..< state.height:
      let srcY = min((y * comp.height) div state.height, comp.height - 1)
      for x in 0 ..< state.width:
        let srcX = min((x * comp.width) div state.width, comp.width - 1)
        let value = int(comp.plane[srcY * comp.width + srcX])
        img.setPixel(x, y, value, value, value)
    return img

  let yComp = state.components[0]
  let cbComp = state.components[1]
  let crComp = state.components[2]
  for y in 0 ..< state.height:
    let ySrc = min((y * yComp.height) div state.height, yComp.height - 1)
    let cbSrc = min((y * cbComp.height) div state.height, cbComp.height - 1)
    let crSrc = min((y * crComp.height) div state.height, crComp.height - 1)
    for x in 0 ..< state.width:
      let yX = min((x * yComp.width) div state.width, yComp.width - 1)
      let cbX = min((x * cbComp.width) div state.width, cbComp.width - 1)
      let crX = min((x * crComp.width) div state.width, crComp.width - 1)
      let Y = int(yComp.plane[ySrc * yComp.width + yX])
      let Cb = int(cbComp.plane[cbSrc * cbComp.width + cbX])
      let Cr = int(crComp.plane[crSrc * crComp.width + crX])
      let pixel = yCbCrToRgb(Y, Cb, Cr)
      img.setPixel(x, y, int(pixel.r), int(pixel.g), int(pixel.b))
  img

# Public API -----------------------------------------------------------------

proc decodeJpeg*(data: seq[byte]): Image =
  if data.len < 2:
    raise newException(ValueError, "File too small to be JPEG")
  if ((uint16(data[0]) shl 8) or uint16(data[1])) != soiMarker:
    raise newException(ValueError, "Missing SOI marker")

  var pos = 2
  var state = DecoderState(width: 0, height: 0)

  while pos < data.len:
    let marker = readMarker(data, pos)
    case marker
    of eoiMarker:
      break
    of sof0Marker:
      let length = readUint16(data, pos)
      if pos + length - 2 > data.len:
        raise newException(ValueError, "SOF0 segment exceeds file size")
      let segment = data[pos ..< pos + length - 2]
      pos += length - 2
      parseSOF0(state, segment)
    of dqtMarker:
      let length = readUint16(data, pos)
      if pos + length - 2 > data.len:
        raise newException(ValueError, "DQT segment exceeds file size")
      let segment = data[pos ..< pos + length - 2]
      pos += length - 2
      parseDQT(state, segment)
    of dhtMarker:
      let length = readUint16(data, pos)
      if pos + length - 2 > data.len:
        raise newException(ValueError, "DHT segment exceeds file size")
      let segment = data[pos ..< pos + length - 2]
      pos += length - 2
      parseDHT(state, segment)
    of driMarker:
      let length = readUint16(data, pos)
      if pos + length - 2 > data.len:
        raise newException(ValueError, "DRI segment exceeds file size")
      let segment = data[pos ..< pos + length - 2]
      pos += length - 2
      parseDRI(state, segment)
    of sosMarker:
      let length = readUint16(data, pos)
      if pos + length - 2 > data.len:
        raise newException(ValueError, "SOS segment exceeds file size")
      let segment = data[pos ..< pos + length - 2]
      pos += length - 2
      parseSOS(state, segment)
      let entropyStart = pos
      var entropyEnd = entropyStart
      while entropyEnd + 1 < data.len:
        if data[entropyEnd] == 0xFF'u8:
          let next = data[entropyEnd + 1]
          if next == 0x00'u8:
            entropyEnd += 2
            continue
          if next >= rstMarkerStartByte and next <= rstMarkerEndByte:
            entropyEnd += 2
            continue
          break
        inc entropyEnd
      let entropyData = data[entropyStart ..< entropyEnd]
      decodeScan(state, entropyData)
      pos = entropyEnd
    else:
      let length = readUint16(data, pos)
      if pos + length - 2 > data.len:
        raise newException(ValueError, "Segment exceeds file size")
      pos += length - 2
  if state.width == 0 or state.height == 0:
    raise newException(ValueError, "SOF0 segment missing")
  assembleImage(state)


proc loadJpeg*(path: string): Image =
  if not os.fileExists(path):
    raise newException(OSError, "File not found: " & path)
  let raw = readFile(path)
  var bytes = newSeq[byte](raw.len)
  for i in 0 ..< raw.len:
    bytes[i] = byte(raw[i])
  decodeJpeg(bytes)
