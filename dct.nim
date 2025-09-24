import std/math

import common

let cosTable = block:
  var table: array[BlockDim, array[BlockDim, float64]]
  for u in 0 ..< BlockDim:
    for x in 0 ..< BlockDim:
      table[u][x] = cos((PI / 16.0) * float((2 * x + 1) * u))
  table

let cScale = block:
  var scale: array[BlockDim, float64]
  for i in 0 ..< BlockDim:
    if i == 0:
      scale[i] = 1.0 / sqrt(2.0)
    else:
      scale[i] = 1.0
  scale

# -----------------------------------------------------------------------------

proc forwardDCT*(input: SampleBlock): IntBlock =
  ## Perform a 2D DCT on a block that has already been level-shifted.
  var tmp: array[BlockSize, float64]

  # Horizontal pass
  for y in 0 ..< BlockDim:
    for u in 0 ..< BlockDim:
      var sum = 0.0
      for x in 0 ..< BlockDim:
        sum += float64(input[y * BlockDim + x]) * cosTable[u][x]
      tmp[y * BlockDim + u] = sum

  # Vertical pass
  for u in 0 ..< BlockDim:
    for v in 0 ..< BlockDim:
      var sum = 0.0
      for y in 0 ..< BlockDim:
        sum += tmp[y * BlockDim + u] * cosTable[v][y]
      let value = 0.25 * cScale[u] * cScale[v] * sum
      result[v * BlockDim + u] = int32(round(value))


proc inverseDCT*(input: IntBlock): SampleBlock =
  ## Perform the inverse DCT, returning level-shifted spatial samples.
  var tmp: array[BlockSize, float64]

  # Vertical pass (frequency rows -> spatial rows)
  for u in 0 ..< BlockDim:
    for y in 0 ..< BlockDim:
      var sum = 0.0
      for v in 0 ..< BlockDim:
        sum += cScale[v] * float64(input[v * BlockDim + u]) * cosTable[v][y]
      tmp[y * BlockDim + u] = sum

  # Horizontal pass
  for y in 0 ..< BlockDim:
    for x in 0 ..< BlockDim:
      var sum = 0.0
      for u in 0 ..< BlockDim:
        sum += cScale[u] * tmp[y * BlockDim + u] * cosTable[u][x]
      let value = 0.25 * sum
      result[y * BlockDim + x] = int16(round(value))

