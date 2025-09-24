import common, bitstream

# Build canonical Huffman tables ---------------------------------------------

proc buildHuffmanTable*(codeLengths: openArray[int], values: openArray[int]): HuffmanTable =
  assert codeLengths.len == 16
  var table: HuffmanTable
  table.fastBits = DefaultFastBits
  table.fastMask = (1 shl table.fastBits) - 1
  table.fastLookup = newSeq[int16](1 shl table.fastBits)
  table.fastCodeLen = newSeq[uint8](1 shl table.fastBits)
  table.values = newSeq[int16](values.len)
  for i in 0 ..< values.len:
    table.values[i] = int16(values[i])

  var code = 0'i32
  var k = 0
  for length in 1 .. 16:
    code = code shl 1
    let count = codeLengths[length - 1]
    if count == 0:
      table.minCode[length] = -1
      table.maxCode[length] = -1
      continue

    table.minCode[length] = code
    table.valPtr[length] = int32(k)

    for j in 0 ..< count:
      let symbol = values[k + j]
      table.codes[symbol] = uint16(code)
      table.codeLengths[symbol] = uint8(length)

      if length <= table.fastBits:
        let shift = table.fastBits - length
        let start = int(code shl shift)
        let finish = int((code + 1) shl shift)
        for idx in start ..< finish:
          table.fastLookup[idx] = int16(symbol)
          table.fastCodeLen[idx] = uint8(length)

      inc code

    table.maxCode[length] = code - 1
    k += count

  table


proc decodeSymbol*(br: var BitReader, table: HuffmanTable): int =
  discard ensureBits(br, table.fastBits)

  var peek: int
  if br.bits >= table.fastBits:
    peek = int((br.acc shr (br.bits - table.fastBits)) and uint32(table.fastMask))
  else:
    let shift = table.fastBits - br.bits
    peek = int((br.acc shl shift) and uint32(table.fastMask))

  let fastLen = int(table.fastCodeLen[peek])
  if fastLen != 0:
    br.bits -= fastLen
    if br.bits == 0:
      br.acc = 0
    else:
      br.acc = br.acc and ((1'u32 shl br.bits) - 1)
    return int(table.fastLookup[peek])

  var code = 0'i32
  var length = 0
  while length < 16:
    let bit = getBit(br)
    if bit < 0:
      return -1
    code = (code shl 1) or int32(bit)
    inc length
    if code <= table.maxCode[length]:
      let idx = table.valPtr[length] + (code - table.minCode[length])
      if idx >= table.values.len:
        return -1
      return int(table.values[idx])
  return -1


proc encodeSymbol*(bw: var BitWriter, table: HuffmanTable, symbol: int) =
  let length = table.codeLengths[symbol]
  let code = int(table.codes[symbol])
  if length == 0:
    raise newException(ValueError, "Huffman symbol not present in table")
  putBits(bw, code, int(length))
