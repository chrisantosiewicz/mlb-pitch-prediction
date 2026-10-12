# In-game adaptation: postseason replays

*Original model vs. the in-game model (adapts to what the pitcher has thrown earlier in the same game). Neither game was used in training. Pitches are predicted from their pre-pitch state only.*

## By game

| game | pitches | original model | in-game model | usual mix | original log loss | in-game log loss |
|---|---|---|---|---|---|---|
| 849831 | 257 | 35.8% | 37.0% | 35.0% | 1.503 | 1.374 |
| 849832 | 368 | 44.8% | 45.7% | 46.5% | 1.180 | 1.140 |

## Starters vs. relievers

| game | role | pitches | original model | in-game model | usual mix | original log loss | in-game log loss |
|---|---|---|---|---|---|---|---|
| 849831 | reliever | 92 | 47.8% | 44.6% | 40.2% | 1.257 | 1.138 |
| 849831 | starter | 165 | 29.1% | 32.7% | 32.1% | 1.641 | 1.505 |
| 849832 | reliever | 276 | 45.3% | 46.4% | 46.7% | 1.178 | 1.135 |
| 849832 | starter | 92 | 43.5% | 43.5% | 45.7% | 1.185 | 1.154 |

## Curveballs

| game | curveballs | original model | in-game model |
|---|---|---|---|
| 849831 | 53 | 24.5% | 26.4% |
| 849832 | 29 | 31.0% | 31.0% |

## By pitcher

| game | pitcher_name | pitches | original model | in-game model | usual mix | original log loss | in-game log loss |
|---|---|---|---|---|---|---|---|
| 849831 | Gavin Williams | 94 | 28.7% | 28.7% | 31.9% | 1.517 | 1.448 |
| 849831 | Sean Burke | 71 | 29.6% | 38.0% | 32.4% | 1.805 | 1.581 |
| 849831 | Cade Smith | 27 | 55.6% | 51.9% | 51.9% | 1.055 | 0.905 |
| 849831 | Hunter Gaddis | 24 | 41.7% | 41.7% | 25.0% | 1.295 | 1.228 |
| 849831 | Sean Newcomb | 23 | 47.8% | 39.1% | 39.1% | 1.195 | 1.227 |
| 849831 | Grant Taylor | 13 | 30.8% | 23.1% | 23.1% | 1.888 | 1.519 |
| 849831 | Erik Sabrowski | 5 | 80.0% | 100.0% | 100.0% | 0.802 | 0.570 |
| 849832 | Parker Messick | 65 | 40.0% | 41.5% | 44.6% | 1.248 | 1.211 |
| 849832 | Erick Fedde | 61 | 29.5% | 41.0% | 49.2% | 1.412 | 1.302 |
| 849832 | Cade Smith | 31 | 61.3% | 64.5% | 67.7% | 0.699 | 0.734 |
| 849832 | Hagen Smith | 27 | 51.9% | 48.1% | 48.1% | 1.033 | 1.017 |
| 849832 | Tyler Davis | 27 | 44.4% | 48.1% | 44.4% | 1.054 | 0.997 |
| 849832 | Shawn Armstrong | 19 | 36.8% | 31.6% | 36.8% | 1.098 | 1.108 |
| 849832 | Gavin Williams | 18 | 72.2% | 61.1% | 38.9% | 1.020 | 0.986 |
| 849832 | Grant Taylor | 18 | 22.2% | 22.2% | 22.2% | 1.789 | 1.708 |
| 849832 | Erik Sabrowski | 17 | 88.2% | 94.1% | 88.2% | 0.465 | 0.428 |
| 849832 | Bryan Hudson | 16 | 37.5% | 37.5% | 37.5% | 1.084 | 0.986 |
| 849832 | Hunter Gaddis | 16 | 37.5% | 37.5% | 37.5% | 1.257 | 1.341 |
| 849832 | Tanner Bibee | 15 | 46.7% | 46.7% | 40.0% | 1.636 | 1.658 |
| 849832 | Jordan Hicks | 14 | 35.7% | 21.4% | 21.4% | 1.225 | 1.153 |
| 849832 | Tim Herrin | 13 | 53.8% | 46.2% | 46.2% | 1.224 | 1.124 |
| 849832 | Anthony Kay | 11 | 54.5% | 45.5% | 54.5% | 1.322 | 1.315 |

