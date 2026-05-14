# TT-16 performance/cost model

## Measured core cycles

| decrypt | AD bytes | message bytes | cycles |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 31 |
| 0 | 0 | 1 | 32 |
| 0 | 0 | 8 | 32 |
| 0 | 0 | 16 | 42 |
| 0 | 0 | 32 | 53 |
| 0 | 8 | 8 | 43 |
| 0 | 16 | 16 | 63 |
| 0 | 32 | 32 | 85 |
| 1 | 0 | 16 | 42 |
| 1 | 16 | 16 | 63 |
| 1 | 32 | 32 | 85 |

## Headline case

Using decrypt=0, AD=32 B, message=32 B, cycles=85.
