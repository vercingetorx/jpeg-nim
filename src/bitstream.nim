# Entropy bit reader ---------------------------------------------------------

type
  BitReader* = object
    data*: seq[byte]
    pos*: int
    acc*: uint32
    bits*: int
    eof*: bool
    marker*: int            # holds the marker code (lower byte) when encountered

proc initBitReader*(data: seq[byte]): BitReader =
  BitReader(data: data, pos: 0, acc: 0'u32, bits: 0, eof: false, marker: -1)


proc readByte(br: var BitReader): int {.inline.} =
  if br.eof or br.pos >= br.data.len:
    br.eof = true
    return -1

  var b = br.data[br.pos]
  inc br.pos

  if b != 0xFF'u8:
    return int(b)

  # Handle marker stuffing. There can be multiple 0xFF in a row (fill).
  while true:
    if br.pos >= br.data.len:
      br.eof = true
      return -1

    let next = br.data[br.pos]
    inc br.pos

    case next
    of 0x00'u8:
      return 0xFF
    of 0xD0'u8 .. 0xD7'u8:  # Restart markers, reset accumulator and continue.
      br.acc = 0
      br.bits = 0
      return readByte(br)
    of 0xFF'u8:
      continue  # additional fill byte
    else:
      br.marker = int(next)
      br.eof = true
      return -1


proc ensureBits*(br: var BitReader, count: int): bool {.inline.} =
  ## Pull bytes into the accumulator until we have at least `count` bits.
  while br.bits < count:
    let byte = readByte(br)
    if byte < 0:
      return false
    br.acc = (br.acc shl 8) or uint32(byte)
    br.bits += 8
  true


proc getBits*(br: var BitReader, count: int): int {.inline.} =
  ## Read `count` bits, MSB first. Returns -1 on EOF.
  if count == 0:
    return 0
  if not ensureBits(br, count):
    return -1
  let shift = br.bits - count
  let mask = (1'u32 shl count) - 1
  let value = (br.acc shr shift) and mask
  br.bits = shift
  if shift == 0:
    br.acc = 0
  else:
    br.acc = br.acc and ((1'u32 shl shift) - 1)
  int(value)


proc getBit*(br: var BitReader): int {.inline.} =
  getBits(br, 1)


proc discardBits*(br: var BitReader) {.inline.} =
  ## Drop any partially read bits so that the next byte boundary begins fresh.
  br.bits = 0
  br.acc = 0

# Entropy bit writer ---------------------------------------------------------

type
  BitWriter* = object
    buffer*: seq[byte]
    acc*: uint32
    bits*: int

proc initBitWriter*(): BitWriter =
  BitWriter(buffer: @[], acc: 0'u32, bits: 0)


proc flushByte(bw: var BitWriter, value: uint8) {.inline.} =
  bw.buffer.add(value)
  if value == 0xFF'u8:
    bw.buffer.add(0x00'u8)


proc putBits*(bw: var BitWriter, value: int, count: int) {.inline.} =
  ## Append `count` most significant bits from `value` to the bitstream.
  var remaining = count
  while remaining > 0:
    remaining.dec()
    let bit = (value shr remaining) and 1
    bw.acc = (bw.acc shl 1) or uint32(bit)
    inc bw.bits
    if bw.bits == 8:
      flushByte(bw, uint8(bw.acc and 0xFF))
      bw.bits = 0
      bw.acc = 0


proc flushBits*(bw: var BitWriter) {.inline.} =
  ## Flush any remaining bits to the output, padding with ones as per JPEG.
  if bw.bits > 0:
    let padBits = 8 - bw.bits
    bw.acc = (bw.acc shl padBits) or ((1'u32 shl padBits) - 1)
    flushByte(bw, uint8(bw.acc and 0xFF))
    bw.bits = 0
    bw.acc = 0
