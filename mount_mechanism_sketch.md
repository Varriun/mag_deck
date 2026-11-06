# Mount mechanism sketch (scratchpad)

Working file for sketching the magnet-mount-to-controller mechanism (Spigen MagSafe ring/holder + hinged arm idea). Edit freely — add hinges, change arm shape, add a second view, whatever gets the idea across. I'll read back whatever you draw.

Legend (suggested, change as needed):
```
[====]   rigid plate / body
  o      hinge pivot point
  |  /   \  -    links, arms, rails
 (( ))    magnet ring
```

---

## View 1 — top down view

```

     ____________________________________________________________________________
    |  [L1]   (L2)                                              (R2)       [R1]  |
    |                                                                            |
    |      D-PAD             START                  SELECT             ABXY      |
    |          ^                        .--.                            Y        |
    |       <     >                    (    )                         X   B      |
    |          v                        '--'                            A        |
    |                                                                            |
    |      .-------------.                                 .-------------.       |
    |      |             |                                 |             |       |
    |      |  TRACKPAD-L |                                 |  TRACKPAD-R |       |
    |      |             |                                 |             |       |
    |      |             |                                 |             |       |
    |      '-------------'                                 '-------------'       |
    |____________________________________________________________________________|
 

```
The smaller ring is a hinge embedded in the plate, allowing the controller to and the arm attatched to the smaller ring to be adjusted 360 degrees around it.
the mentioned arm is a connected via a heavy duty hinge to let the arm and the bigger magsafe ring fold out from the main body.


## View 2 — Side view
One hinge on the smaller ring inside, allowing adjustment of the controller 360 degrees around the arm.
The second hinge is connected to a thick magsafe ring.

By adjusting the position of the magsafe manually (it's a magnet, you can detach and put back at any angle), and the circular joint on the plate, it theoretically can support any and all orientations.
```
When open:                                                 When Closed:
             _                                                              
            | |                                                             
            | |                                                             
            | |                                                             
            | |                                                             
            | |                                                             
            | |                                                             
            |_|                                                             
           O                                             
          /                                             
         /                                              
        /                                               
       /                                                
 _    /                                              _  
| |  /                                              | |  _ 
| |O/                                               | |O| |
| |                                                 | ||| |
| |                                                 | ||| |
| |                                                 | ||| |
| |                                                 | ||| |
| |                                                 | ||| |
| |                                                 | |O|_|
| |                                                 | |
| |                                                 | |
| |                                                 | |
| |                                                 | |
| |                                                 | |
|_|                                                 |_|   

```

---

## View 3 — Fold 8 back sides (draw the ring/arm placement on these)

Both boxes now in landscape (matching how you'd actually hold it to game). Camera and typical case-MagSafe-ring positions are marked as a starting approximation -- eyeballed proportionally, not measured off a real spec drawing, so nudge them once you have exact coordinates.

Box 1 = closed state, the whole back is one panel (camera + case magnet zone both live here).
Box 2 = unfolded, rotated to landscape. The hinge crease becomes the vertical divider: left half is the cover-display panel now facing backward (it was the front screen when closed), right half is the same camera/backside panel as Box 1 -- camera and magnet zone only appear on that half, not the screen half.
```
Z FOLD 8 -- CLOSED, back side, landscape orientation (123.9mm x 81.9mm)



Z FOLD 8 -- OPEN (unfolded), rotated to landscape (161.4mm x 123.9mm)
```

---

## Notes / constraints to keep in mind while sketching
- Magnet plate stays fixed to the phone's back cover regardless of fold state.
- Controller plate is what your hands actually grip — needs to feel rigid during gameplay, not floppy.
- Only 2 known phones to support: S23 Ultra (slab) and Z Fold 8 (folded = landscape, unfolded = portrait-ish).
- Whatever this mechanism turns into, it's a CAD/mechanical question — doesn't affect the single-PCB electrical design already locked in.
