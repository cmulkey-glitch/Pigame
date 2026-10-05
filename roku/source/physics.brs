' Tunable player physics (BrightScript version of src/game/physics.js). The defaults are the
' 7800 ROM's values; a level pack's "physics" object overrides any of them.

function Physics_rom() as object
    return {
        stepFrames: 4, walkSpeed: 1, airSpeed: 1, jumpSpeed: 5.5, gravity: 0.75
        maxFallSpeed: 7, deadlyFallSpeed: 7, climbUpSpeed: 1, climbDownSpeed: 2
        ropeHoldSteps: 6, wallBounce: 1, airControl: 0
    }
end function

' A complete parameter set plus the ROM's 8.8 fixed-point forms used by player.brs.
function Physics_from(p as object) as object
    ph = Physics_rom()
    if p <> invalid then
        for each k in p
            ph[k] = p[k]
        end for
    end if
    ph.jumpVy = Cint(ph.jumpSpeed * 256)                         ' $0580
    ph.gravityFixed = Cint(ph.gravity * 256)                     ' $00C0
    ph.terminalHi = (256 - Cint(ph.maxFallSpeed)) and &hFF       ' $F9
    ph.safeHi = (256 - (Cint(ph.deadlyFallSpeed) - 1)) and &hFF  ' $FA
    return ph
end function
