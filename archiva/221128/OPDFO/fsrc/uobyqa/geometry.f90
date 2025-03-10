module geometry_mod
!--------------------------------------------------------------------------------------------------!
! This module contains subroutines concerning the geometry-improving of the interpolation set XPT.
!
! Coded by Zaikun ZHANG (www.zhangzk.net) based on Powell's code and the UOBYQA paper.
!
! Dedicated to late Professor M. J. D. Powell FRS (1936--2015).
!
! Started: February 2022
!
! Last Modified: Thursday, November 10, 2022 PM04:07:24
!--------------------------------------------------------------------------------------------------!

implicit none
private
public :: geostep


contains


subroutine geostep(g, h, delbar, d, vmax)

! Generic modules
use, non_intrinsic :: consts_mod, only : RP, IK, ZERO, ONE, HALF, QUART, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_nan
use, non_intrinsic :: linalg_mod, only : issymmetric, matprod, inprod

implicit none

! Inputs
real(RP), intent(in) :: g(:)  ! G(N)
real(RP), intent(in) :: h(:, :)  ! H(N, N)
real(RP), intent(in) :: delbar

! Outputs
real(RP), intent(out) :: d(:)  ! D(N)
real(RP), intent(out) :: vmax

! Local variables
character(len=*), parameter :: srname = 'GEOSTEP'
integer(IK) :: n
real(RP) :: v(size(g)), dcauchy(size(g))
real(RP) :: dd, dhd, dlin, gd, gg, ghg, gnorm, &
&        ratio, scaling, temp, &
&        tempa, tempb, tempc, tempd, tempv, vhg, vhv, vhd, &
&        vlin, vmu, vnorm, vv, wcos, wsin, hv(size(g))
integer(IK) :: k


! Sizes.
n = int(size(g), kind(n))

if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(delbar > 0, 'DELBAR > 0', srname)
    call assert(size(h, 1) == n .and. issymmetric(h), 'H is n-by-n and symmetric', srname)
    call assert(size(d) == n, 'SIZE(D) == N', srname)
end if

!
!     N is the number of variables of a quadratic objective function, Q say.
!     G is the gradient of Q at the origin.
!     H is the symmetric Hessian matrix of Q. Only the upper triangular and
!       diagonal parts need be set.
!     DELBAR is the trust region radius, and has to be positive.
!     D will be set to the calculated vector of variables.
!     The array V will be used for working space.
!     VMAX will be set to |Q(0)-Q(D)|.
!
!     Calculating the D that maximizes |Q(0)-Q(D)| subject to ||D|| .LEQ. DELBAR
!     requires of order N**3 operations, but sometimes it is adequate if
!     |Q(0)-Q(D)| is within about 0.9 of its greatest possible value. This
!     subroutine provides such a solution in only of order N**2 operations,
!     where the claim of accuracy has been tested by numerical experiments.
!
!     Preliminary calculations.
!

gg = sum(g**2)
ghg = inprod(g, matprod(h, g))
dcauchy = (delbar / sqrt(gg)) * g
if (ghg < 0) then
    dcauchy = -dcauchy
end if
where (is_nan(dcauchy)) dcauchy = ZERO

if (is_nan(sum(abs(h)) + sum(abs(g)))) then
    !d = ZERO
    d = dcauchy
    vmax = ZERO
    return
end if

! Pick V such that ||HV|| / ||V|| is large.
k = int(maxloc(sum(h**2, dim=1), dim=1), IK)
v = h(:, k)

! Set D to a vector in the subspace span{V, HV} that maximizes |(D, HD)|/(D, D), except that we set
! D = HV if V and HV are nearly parallel.
vv = sum(v**2)
d = matprod(h, v)
vhv = inprod(v, d)
if (vhv * vhv <= 0.9999_RP * sum(d**2) * vv) then
    d = d - (vhv / vv) * v
    dd = sum(d**2)
    ratio = sqrt(dd / vv)
    dhd = inprod(d, matprod(h, d))
    v = ratio * v
    vhv = ratio * ratio * vhv
    vhd = ratio * dd
    temp = HALF * (dhd - vhv)
    if (dhd + vhv < 0) then
        d = vhd * v + (temp - sqrt(temp**2 + vhd**2)) * d
    else
        d = vhd * v + (temp + sqrt(temp**2 + vhd**2)) * d
    end if
end if

! We now turn our attention to the subspace span{G, D}. A multiple of the current D is returned if
! that choice seems to be adequate.
gg = sum(g**2)
gd = inprod(g, d)
dd = sum(d**2)
dhd = inprod(d, matprod(h, d))

! Zaikun 20220504: GG and DD can become 0 at this point due to rounding. Detected by IFORT.
if (.not. (gg > 0 .and. dd > 0)) then
    !d = ZERO
    d = dcauchy
    vmax = ZERO
    return
end if

v = d - (gd / gg) * g
vv = sum(v**2)
if (gd * dhd < 0) then
    scaling = -delbar / sqrt(dd)
else
    scaling = delbar / sqrt(dd)
end if
d = scaling * d
gnorm = sqrt(gg)
where (is_nan(d)) d = ZERO

if (.not. (gnorm * dd > 0.5E-2_RP * delbar * abs(dhd) .and. vv > 1.0E-4_RP * dd)) then
    vmax = abs(scaling * (gd + HALF * scaling * dhd))
    if (sum(d**2) <= 0) d = dcauchy
    return
end if

! G and V are now orthogonal in the subspace span{G, D}. Hence we generate an orthonormal basis of
! this subspace such that (D, HV) is negligible or 0, where D and V will be the basis vectors.
ghg = inprod(g, matprod(h, g))
hv = matprod(h, v)
vhg = inprod(g, hv)
vhv = inprod(v, hv)
vnorm = sqrt(vv)
ghg = ghg / gg
vhg = vhg / (vnorm * gnorm)
vhv = vhv / vv
if (abs(vhg) <= 0.01_RP * max(abs(ghg), abs(vhv))) then
    vmu = ghg - vhv
    wcos = ONE
    wsin = ZERO
else
    temp = HALF * (ghg - vhv)
    if (temp < 0) then
        vmu = temp - sqrt(temp**2 + vhg**2)
    else
        vmu = temp + sqrt(temp**2 + vhg**2)
    end if
    temp = sqrt(vmu**2 + vhg**2)
    wcos = vmu / temp
    wsin = vhg / temp
end if
tempa = wcos / gnorm
tempb = wsin / vnorm
tempc = wcos / vnorm
tempd = wsin / gnorm
d = tempa * g + tempb * v
v = tempc * v - tempd * g

! The final D is a multiple of the current D, V, D + V or D - V. We make the choice from these
! possibilities that is optimal.
dlin = wcos * gnorm / delbar
vlin = -wsin * gnorm / delbar
tempa = abs(dlin) + HALF * abs(vmu + vhv)
tempb = abs(vlin) + HALF * abs(ghg - vmu)
tempc = sqrt(HALF) * (abs(dlin) + abs(vlin)) + QUART * abs(ghg + vhv)
if (tempa >= tempb .and. tempa >= tempc) then
    if (dlin * (vmu + vhv) < 0) then
        tempd = -delbar
    else
        tempd = delbar
    end if
    tempv = ZERO
else if (tempb >= tempc) then
    tempd = ZERO
    if (vlin * (ghg - vmu) < 0) then
        tempv = -delbar
    else
        tempv = delbar
    end if
else
    if (dlin * (ghg + vhv) < 0) then
        tempd = -sqrt(HALF) * delbar
    else
        tempd = sqrt(HALF) * delbar
    end if
    if (vlin * (ghg + vhv) < 0) then
        tempv = -sqrt(HALF) * delbar
    else
        tempv = sqrt(HALF) * delbar
    end if
end if
d = tempd * d + tempv * v
where (is_nan(d)) d = ZERO
vmax = delbar * delbar * max(tempa, tempb, tempc)
if (sum(d**2) <= 0) d = dcauchy

end subroutine geostep


end module geometry_mod
