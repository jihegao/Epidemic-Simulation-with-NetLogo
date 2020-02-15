extensions [csv]

globals [
  min_lon max_lon min_lat max_lat
  mortality
  totalCoverage
  numEmptyBeds
  numEmptyRooms
  stayAtHome?
  quarantine?
]

breed [ provinces province ]
breed [ cities city ]
breed [ persons person ]

;breed [  ]

provinces-own [
  name
  population
]

cities-own [
  name
  population
  prov
]

persons-own [
  status ; 0 - susceptible, 1 - latency 2 - onset, -1 - resist -2 dead

  infected-time  ; ticks
  todaysContacts ; who this person has daily interaction

  suspected?     ; 疑似
  confirmed?     ; 确诊
  quarantined?   ; d隔离
  hospitalized?  ; 收治
  quarantineBeginTime  ; 隔离开始时间
]


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


to setup
  clear-all
  reset-ticks
  set quarantine? false
  set stayAtHome? false
  ask patches [set pcolor white]
  ask patch 92 98 [set plabel (word "Day " ticks) set plabel-color black]
  init-one-community
  init-beds
  ;init-cities
  init-outbreak
  set totalCoverage map [? -> [status] of ?] sort persons
end


to init-outbreak
  ask one-of persons [set-status 1]
  if false [
    ask cities with [name = "武汉市"][
      ask one-of persons-here [
        set-status 1
      ]
    ]
  ]
end

to go
  if not any? persons with [status > 0][stop]
  ask patch 92 98 [set plabel (word "Day " ticks)]

  community-spread
  becomeOnset
  prevent-and-control
  infectedPersonsRecover
;  incity-spread
;  intercity-travel
;  update-city-colors
  tick
end

to update-city-colors
  ask cities with [infection-rate > 0][
    set color scale-color red infection-rate 2 -1
  ]
end

to-report infection-rate
  report count persons with [status > 0] / numPerson
end


to prevent-and-control
  detect
  quarantine
  preventCommuting
  treat
end

to detect
  ; strategy of finding suspect patients:
  ; "default" - base on onset symptoms
  ; ""
  ask persons with [ status = 2 and not hospitalized? ][
    set suspected? true
  ]

  ; strategy of screening infected persons:
  ; "default" - only screening suspected person
  ask persons with [ suspected? ][
    if (random-float 1 >= falseNegativeRate)[
      set confirmed? true
      set suspected? false
    ]
  ]
end

to quarantine
  ; quarantine onset patients start at number of infection percentage >= quarantineStartThreshold
  ; if with enough treatment beds
  if infection-rate >= quarantineStartThreshold [ set quarantine? true ]
  if quarantine? [
    let numDeployedBeds ifelse-value (numEmptyBeds > count persons with [confirmed? and not hospitalized?])
                          [ count persons with [confirmed? and not hospitalized?] ]
                          [ ifelse-value (numEmptyBeds > 0) [numEmptyBeds][0] ]
    ask n-of numDeployedBeds persons with [confirmed? and not hospitalized?][
      set hospitalized? true
    ]
  ]

  ; quarantine suspected patients
  if (quarantine? and quarantineSuspected?) [
    let numDeployedRooms ifelse-value (numEmptyRooms > count persons with [suspected? and not quarantined?])
                          [ count persons with [suspected? and not quarantined?] ]
                          [ ifelse-value (numEmptyRooms > 0) [numEmptyRooms][0] ]
    ask n-of numDeployedRooms persons with [suspected? and not quarantined?][
      set quarantined? true
      set quarantineBeginTime ticks
    ]
  ]

  ; quarantine contacts
  if (quarantine? and quarantineContacts?) [
    let allContacts (turtle-set [todaysContacts] of persons with [(suspected? or hospitalized?) and status > -2])
    if any? allContacts [
      let numDeployedRooms ifelse-value (numEmptyRooms > count allContacts)
                            [ count allContacts ]
                            [ ifelse-value (numEmptyRooms > 0) [numEmptyRooms][0] ]
      ask n-of numDeployedRooms allContacts [
        set quarantined? true
        set quarantineBeginTime ticks
      ]
    ]
  ]

  ; quit quarantine
  ask persons with [ quarantined? ][
    if quarantined-days >= (latencyPeriod + onsetPeriod) or hospitalized? [
      set quarantined? false
      set quarantineBeginTime 0
    ]
  ]

  ; update available beds and rooms
  set numEmptyBeds numBeds - count persons with [hospitalized?]
  set numEmptyRooms numQuarantineRooms - count persons with [quarantined?]

end

to preventCommuting
  if infection-rate > stayAtHomeThreshold [
    set stayAtHome? true
  ]
end

to treat
  ask persons with [hospitalized? and random-float 1 < curedRate ][
    set-status ifelse-value (random-float 1 < falseNegativeRate)[1][ recoveredStatus ]
    set hospitalized? false
    set confirmed? false
  ]
end

to infectedPersonsRecover
  ask persons with [status = 2][
    ; end of infection (latency + onset) period
    if (infected-days >= (2 + random latencyPeriod + 2 + random onsetPeriod)) [
      set confirmed? false
      set hospitalized? false
      set quarantined? false

      ; dead
      ifelse (random-float 1 <= deathRate)
      [
        set mortality mortality + 1
        set-status -2
      ]
      ; recovered
      [
        let recoverOutcome recoveredStatus
        set-status recoverOutcome
      ]
    ]
  ]
end


to-report recoveredStatus
  report ifelse-value (random-float 1 <= deathRate)
  [-2]
  [
    ifelse-value (random-float 1 <= getResistRatio)[-1][0]
  ]
end


to community-spread
  let spreadingCrowd persons with [ (status > ifelse-value (latencySpread?) [0] [1]) and (not quarantined? and not hospitalized?) ]
  ;show count spreadingCrowd
  ask spreadingCrowd [
    set todaysContacts no-turtles
    ; base on distance
    set todaysContacts up-to-n-of dailyContacts (other persons in-radius dailyActivityDistance with [not quarantined? and not hospitalized?])
    ; base on network
    set todaysContacts ifelse-value ( not stayAtHome? and any? link-neighbors )
    [ (turtle-set todaysContacts link-neighbors with [not quarantined? or not hospitalized?]) ]
    [ todaysContacts ]

    ask todaysContacts with [status = 0][
      if random-float 1 * (ifelse-value ([status] of myself = 1)[3][1]) < spreadRate [
        set-status 1
      ]
    ]
  ]

  update-total-coverage

end


to becomeOnset
  ask persons with [status = 1][
    if (infected-days >= 2 + random latencyPeriod)[set-status 2]
  ]
end

to update-total-coverage
  set totalCoverage (map [[p t] -> ifelse-value ([status] of p > 0)[1] [t] ] sort persons totalCoverage)
end



to intercity-travel
  ask n-of 100 persons [
    let des one-of [link-neighbors] of one-of cities-here
    if des != nobody [
      move-to des
    ]
  ]
end


to-report infected-days
  report ticks - infected-time
end

to-report quarantined-days
  report ticks - quarantineBeginTime
end


to set-status [x]
  set status x
  set-color-based-on-status
  if x = 1 [set infected-time ticks]
end

to set-color-based-on-status
  set color ifelse-value (status = 0)
  [ green ]
  [
    ifelse-value (status = 1)
    [ orange ]
    [ ifelse-value (status = 2)
      [ red ]
      [ ifelse-value (status = -1)
        [ gray ]
        [ black ]
      ]
    ]
  ]
end



to init-one-community
  create-persons numPerson [
    setxy 50 50
    set shape "circle"
    set size 0.6
    set heading random 360
    fd random-float 40
    set-status 0
    set suspected?  false
    set confirmed?   false
    set quarantined?    false
    set hospitalized?   false
    set todaysContacts no-turtles
  ]

  ask one-of persons with [abs (xcor - 50) < 1 and abs (ycor - 50) < 1 ][
    create-link-with one-of other persons
  ]
  while [mean [count my-links] of persons < networkMeanDegree][
    if networkAttachmentMethod = "scale free" [
      ask one-of persons [
        create-link-with [one-of both-ends] of one-of links with [not member? myself both-ends]
      ]
    ]
    if networkAttachmentMethod = "small world" [
      ask n-of round (count persons * networkMeanDegree) persons [
        create-link-with one-of other persons in-radius 10
      ]
      ask n-of (0.05 * count links) links [
        ask one-of both-ends [
          create-link-with one-of other persons with [not member? self [link-neighbors] of myself]
        ]
        die
      ]
    ]
    if networkAttachmentMethod = "random" [
      ask one-of persons [
        create-link-with one-of other persons with [not member? self [link-neighbors] of myself]
      ]
    ]
  ]
end


to init-beds
  set numEmptyBeds numBeds
  set numEmptyRooms numQuarantineRooms
end



to init-cities
  let data but-first csv:from-file "geo-population.csv"
  set min_lon min map [? -> item 1 ?] data - 1
  set max_lon max map [? -> item 1 ?] data + 1
  set min_lat min map [? -> item 2 ?] data - 1
  set max_lat max map [? -> item 2 ?] data + 1

  foreach data [ d ->
    if not any? provinces with [name = item 4 d][
      init-province d
    ]
    if not any? cities with [name = first d][
      init-city d
    ]
  ]
  ask cities with [not any? provinces-here][
    create-link-with one-of cities with [prov = [prov] of myself and any? provinces-here]
;    if (any? other cities with [distance myself < 10]) [
;      create-link-with one-of other cities with [distance myself < 10]
;    ]
  ]
  ask provinces [
    set size (sum [population] of link-neighbors + population) / 2000
    hide-turtle
  ]
  ask turtles [set label-color black]
  foreach sort cities [ c ->
    init-residences ([population] of c) * 10000 / numPersonPerTurtle c
  ]
end

to init-province [d]
  create-provinces 1 [
    set name item 4 d
    set population item 5 d
    set shape "circle"
  ]
end

to init-city [d]
  create-cities 1 [
    set name first d
    ;set label name
    set color gray
    set xcor lon2x item 1 d
    set ycor lat2y item 2 d
    set population item 3 d
    set prov one-of provinces with [name = item 4 d]
    create-link-with prov
    ask prov [
      set population population - [population] of myself
      ; it capital city
      if item 6 d = 1  [ move-to myself ]
    ]
    set shape "circle"
    set size ln (population / 100)
  ]
end

to init-residences [pop homeCity]
  ;every turtle represents 10,000 real people
  create-persons pop [
    hide-turtle
    move-to homeCity
  ]
end

to-report lon2x [lon]
  report max-pxcor * (lon - min_lon) / (max_lon - min_lon)
end

to-report lat2y [lat]
  report max-pycor * (lat - min_lat) / (max_lat - min_lat)
end

to init-travel-route
  let highwayList [
    [ "北京市"    "天津市"    "济南市"    "合肥市"    "南京市"    "上海市"    "杭州市"]
    [ "北京市"    "潍坊市" "临沂市" "淮安市" "南通市" "上海市"]
    [ "哈尔滨市"  "长春市"  "沈阳市" "北京市" "石家庄市" "郑州市" "武汉市" "长沙市" "广州市" "深圳市"]
    [ "上海市" "南京市" "合肥市" "武汉市" "重庆市" "成都市" ]
    [ "南京市" "安庆市" "九江市" "武汉市" "宜昌市" "重庆市"]
  ]
  foreach highwayList [
    hList ->
    let c0 first hList
    set hList but-first hList
    foreach hList [ w ->
      ask cities with [name = c0][
        if any? cities with [name = w] [create-link-with one-of cities with [name = w]]
        set c0 w
      ]
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
242
11
758
528
-1
-1
5.03
1
10
1
1
1
0
0
0
1
0
100
0
100
1
1
1
ticks
30.0

BUTTON
24
30
105
63
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
25
84
106
117
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
243
528
758
670
population
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"susceptible" 1.0 0 -13840069 true "" "plot count persons with [status = 0]"
"latency" 1.0 0 -955883 true "" "plot count persons with [status = 1]"
"onset" 1.0 0 -2674135 true "" "plot count persons with [status = 2]"
"resist" 1.0 0 -7500403 true "" "plot count persons with [status = -1]"
"mortality" 1.0 0 -16777216 true "" "plot mortality"

SLIDER
22
259
194
292
getResistRatio
getResistRatio
0
1
0.5
0.01
1
NIL
HORIZONTAL

SLIDER
22
334
196
367
onsetPeriod
onsetPeriod
0
100
20.0
1
1
NIL
HORIZONTAL

SLIDER
22
222
194
255
spreadRate
spreadRate
0
1
0.37
0.01
1
NIL
HORIZONTAL

SLIDER
22
299
196
332
latencyPeriod
latencyPeriod
0
10
5.0
1
1
NIL
HORIZONTAL

SLIDER
23
369
196
402
deathRate
deathRate
0
1
0.01
0.01
1
NIL
HORIZONTAL

INPUTBOX
23
775
172
835
numPersonPerTurtle
10000.0
1
0
Number

SLIDER
24
495
199
528
dailyContacts
dailyContacts
0
10
4.0
1
1
NIL
HORIZONTAL

PLOT
1056
27
1256
177
Radial distribution
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "clear-plot\nforeach range 100 [ x -> \n  plot count turtles-on patches with [pxcor = x]\n]"

PLOT
1058
188
1258
338
degree distribution
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "histogram [ count my-links] of turtles"

SLIDER
23
582
226
615
networkMeanDegree
networkMeanDegree
0
1
0.2
0.01
1
NIL
HORIZONTAL

SLIDER
24
460
200
493
dailyActivityDistance
dailyActivityDistance
0
10
2.0
1
1
NIL
HORIZONTAL

SWITCH
21
180
177
213
latencySpread?
latencySpread?
0
1
-1000

CHOOSER
23
619
227
664
networkAttachmentMethod
networkAttachmentMethod
"scale free" "small world" "random"
0

TEXTBOX
28
440
178
458
居住地局部传播假设
11
0.0
1

TEXTBOX
27
157
177
175
病毒传播能力假设
11
0.0
1

TEXTBOX
25
562
175
580
网络结构假设
11
0.0
1

PLOT
1059
371
1259
521
totalCoverage
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if is-list? totalCoverage [ plot (sum totalCoverage) / numPerson ]"

INPUTBOX
23
674
172
734
numPerson
10000.0
1
0
Number

SWITCH
783
482
976
515
quarantineContacts?
quarantineContacts?
0
1
-1000

TEXTBOX
784
69
929
87
防控措施
11
0.0
1

SLIDER
783
364
955
397
numBeds
numBeds
0
1000
500.0
100
1
NIL
HORIZONTAL

SWITCH
783
442
976
475
quarantineSuspected?
quarantineSuspected?
0
1
-1000

SLIDER
783
329
955
362
numQuarantineRooms
numQuarantineRooms
0
1000
1000.0
100
1
NIL
HORIZONTAL

SLIDER
784
254
956
287
falsePositiveRate
falsePositiveRate
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
784
289
956
322
falseNegativeRate
falseNegativeRate
0
1
0.05
0.01
1
NIL
HORIZONTAL

SLIDER
784
219
956
252
alikeSyndromeRate
alikeSyndromeRate
0
1
0.3
0.01
1
NIL
HORIZONTAL

SLIDER
783
400
955
433
curedRate
curedRate
0
1
0.1
0.01
1
NIL
HORIZONTAL

MONITOR
784
579
892
624
NIL
numEmptyBeds
17
1
11

MONITOR
897
580
1014
625
numOccupyBeds
numBeds - numEmptyBeds
17
1
11

MONITOR
783
629
904
674
NIL
numEmptyRooms
17
1
11

MONITOR
897
629
1028
674
numOccupyRooms
numQuarantineRooms - numEmptyRooms
17
1
11

CHOOSER
787
525
925
570
screeningStrategy
screeningStrategy
"default" "contacts" "all"
0

SLIDER
784
182
958
215
stayAtHomeThreshold
stayAtHomeThreshold
0
1
0.05
0.01
1
NIL
HORIZONTAL

MONITOR
860
93
957
138
NIL
stayAtHome?
17
1
11

SLIDER
784
145
958
178
quarantineStartThreshold
quarantineStartThreshold
0.001
0.1
0.001
0.001
1
NIL
HORIZONTAL

MONITOR
782
93
857
138
quarantine
quarantine?
17
1
11

MONITOR
763
10
861
55
NIL
infection-rate
17
1
11

@#$#@#$#@
## 0202

+ virus spread on 2D surface
+ immune

## 0205
+ persons live in cities and live in rural part of provinces
+ inter-citie transfer
+ Expose - travel, commuting and between family members

## todo
+ transfer to neighbor provinces
+ 
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
