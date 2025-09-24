import common

const
  ZigzagMap*: array[BlockSize, uint8] = [
    0,  1,  8, 16,  9,  2,  3, 10,
   17, 24, 32, 25, 18, 11,  4,  5,
   12, 19, 26, 33, 40, 48, 41, 34,
   27, 20, 13,  6,  7, 14, 21, 28,
   35, 42, 49, 56, 57, 50, 43, 36,
   29, 22, 15, 23, 30, 37, 44, 51,
   58, 59, 52, 45, 38, 31, 39, 46,
   53, 60, 61, 54, 47, 55, 62, 63
  ]

# -----------------------------------------------------------------------------

proc deZigzag*(coeffs: openArray[int16]): CoeffBlock =
  ## Transform coefficients from zig-zag order into natural row-major order.
  assert coeffs.len == BlockSize
  var outBlock: CoeffBlock
  for i in 0 ..< BlockSize:
    outBlock[int(ZigzagMap[i])] = coeffs[i]
  outBlock


proc zigzag*(coeffs: openArray[int16]): CoeffBlock =
  ## Transform coefficients from natural order into zig-zag order.
  assert coeffs.len == BlockSize
  var outBlock: CoeffBlock
  for i in 0 ..< BlockSize:
    outBlock[i] = coeffs[int(ZigzagMap[i])]
  outBlock
