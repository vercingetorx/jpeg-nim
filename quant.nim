import common

const
  defaultLuminanceQTable*: QuantTable = [
     16'u16, 11, 10, 16, 24,  40,  51,  61,
     12'u16, 12, 14, 19, 26,  58,  60,  55,
     14'u16, 13, 16, 24, 40,  57,  69,  56,
     14'u16, 17, 22, 29, 51,  87,  80,  62,
     18'u16, 22, 37, 56, 68, 109, 103,  77,
     24'u16, 35, 55, 64, 81, 104, 113,  92,
     49'u16, 64, 78, 87, 103, 121, 120, 101,
     72'u16, 92, 95, 98, 112, 100, 103,  99
  ]

  defaultChrominanceQTable*: QuantTable = [
     17'u16, 18, 24, 47, 99, 99, 99, 99,
     18'u16, 21, 26, 66, 99, 99, 99, 99,
     24'u16, 26, 56, 99, 99, 99, 99, 99,
     47'u16, 66, 99, 99, 99, 99, 99, 99,
     99'u16, 99, 99, 99, 99, 99, 99, 99,
     99'u16, 99, 99, 99, 99, 99, 99, 99,
     99'u16, 99, 99, 99, 99, 99, 99, 99,
     99'u16, 99, 99, 99, 99, 99, 99, 99
  ]

# -----------------------------------------------------------------------------

proc qualityScale(quality: int): int {.inline.} =
  ## Map JPEG quality (1..100) to scaling factor.
  if quality < 50:
    return max(1, 5000 div max(quality, 1))
  max(1, 200 - quality * 2)


proc scaleQuantTable*(base: QuantTable, quality: int): QuantTable =
  let scale = qualityScale(clamp(quality, 1, 100))
  for i in 0 ..< BlockSize:
    let value = (int(base[i]) * scale + 50) div 100
    result[i] = uint16(clamp(value, 1, 255))


proc divRoundNearest(value, divisor: int32): int32 {.inline.} =
  assert divisor != 0
  if value >= 0'i32:
    (value + divisor div 2) div divisor
  else:
    -(((-value) + divisor div 2) div divisor)


proc quantizeBlock*(input: openArray[int32], table: QuantTable): CoeffBlock =
  ## Quantise a frequency block according to the provided table.
  assert input.len == BlockSize
  for i in 0 ..< BlockSize:
    let q = int32(table[i])
    let value = divRoundNearest(input[i], q)
    result[i] = int16(clamp(value, int32(low(int16)), int32(high(int16))))


proc dequantizeBlock*(input: CoeffBlock, table: QuantTable): IntBlock =
  ## Expand a quantised block back to integer frequency domain.
  for i in 0 ..< BlockSize:
    result[i] = int32(input[i]) * int32(table[i])

