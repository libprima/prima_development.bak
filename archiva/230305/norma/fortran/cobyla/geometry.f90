module geometry_mod
!--------------------------------------------------------------------------------------------------!
! This module contains subroutines concerning the geometry-improving of the interpolation set.
!
! Coded by Zaikun ZHANG (www.zhangzk.net) based on Powell's code and the COBYLA paper.
!
! Dedicated to late Professor M. J. D. Powell FRS (1936--2015).
!
! Started: July 2021
!
! Last Modified: Wednesday, February 01, 2023 PM06:40:42
!--------------------------------------------------------------------------------------------------!

implicit none
private
public :: assess_geo, setdrop_geo, setdrop_tr, geostep


contains


function assess_geo(delta, factor_alpha, factor_beta, sim, simi) result(adequate_geo)
!--------------------------------------------------------------------------------------------------!
! This function checks if an interpolation set has acceptable geometry as (14) of the COBYLA paper.
!--------------------------------------------------------------------------------------------------!
! List of local arrays (including function-output arrays; likely to be stored on the stack):
! REAL(RP) :: VETA(N), VSIG(N)
! Size of local arrays: REAL(RP)*(2*N)
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : IK, RP, ONE, TENTH, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_finite
use, non_intrinsic :: linalg_mod, only : isinv

implicit none

! Inputs
real(RP), intent(in) :: delta
real(RP), intent(in) :: factor_alpha
real(RP), intent(in) :: factor_beta
real(RP), intent(in) :: sim(:, :)   ! SIM(N, N+1)
real(RP), intent(in) :: simi(:, :)  ! SIMI(N, N)

! Outputs
logical :: adequate_geo

! Local variables
character(len=*), parameter :: srname = 'ASSESS_GEO'
integer(IK) :: n
real(RP) :: veta(size(sim, 1))
real(RP) :: vsig(size(sim, 1))
real(RP), parameter :: itol = TENTH

! Sizes
n = int(size(sim, 1), kind(n))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(size(sim, 1) == n .and. size(sim, 2) == n + 1, 'SIZE(SIM) == [N, N+1]', srname)
    call assert(all(is_finite(sim)), 'SIM is finite', srname)
    call assert(all(maxval(abs(sim(:, 1:n)), dim=1) > 0), 'SIM(:, 1:N) has no zero column', srname)
    call assert(size(simi, 1) == n .and. size(simi, 2) == n, 'SIZE(SIMI) == [N, N]', srname)
    call assert(all(is_finite(simi)), 'SIMI is finite', srname)
    call assert(isinv(sim(:, 1:n), simi, itol), 'SIMI = SIM(:, 1:N)^{-1}', srname)
    call assert(delta > 0, 'DELTA > 0', srname)
    call assert(factor_alpha > 0 .and. factor_alpha < 1, '0 < FACTOR_ALPHA < 1', srname)
    call assert(factor_beta > 1, 'FACTOR_BETA > 1', srname)
end if

!====================!
! Calculation starts !
!====================!

! Calculate the values of sigma and eta.
! VETA(J) (1 <= J <= N) is the distance between vertices J and 0 (the best vertex) of the simplex.
! VSIG(J) is the distance from vertex J to its opposite face of the simplex. Thus VSIG <= VETA.
! N.B.: What about the distance from vertex N+1 to the its opposite face? Consider the simplex
! {V_{N+1}, V_{N+1} + L*e_1, ..., V_{N+1} + L*e_N}, where V_{N+1} is vertex N+1, namely the current
! "best" point, [e_1, ..., e_n] is an orthogonal matrix, and L is a constant in the order of DELTA.
! This simplex is optimal in the sense that the interpolation system has the minimal condition
! number, i.e., one. For this simplex, the distance from V_{N+1} to its opposite face is L/SQRT{N}.
vsig = ONE / sqrt(sum(simi**2, dim=2))
veta = sqrt(sum(sim(:, 1:n)**2, dim=1))
adequate_geo = all(vsig >= factor_alpha * delta) .and. all(veta <= factor_beta * delta)

!====================!
!  Calculation ends  !
!====================!
end function assess_geo


function setdrop_tr(ximproved, d, delta, factor_alpha, factor_delta, sim, simi) result(jdrop)
!--------------------------------------------------------------------------------------------------!
! This subroutine finds (the index) of a current interpolation point to be replaced by the
! trust-region trial point. See (19)--(22) of the COBYLA paper.
! N.B.:
! 1. If XIMPROVED == TRUE, then JDROP > 0 so that D is included into XPT. Otherwise, it is a bug.
! 2. COBYLA never sets JDROP = N + 1.
!--------------------------------------------------------------------------------------------------!
! List of local arrays (including function-output arrays; likely to be stored on the stack):
! REAL(RP) :: SIGBAR(N), SIMID(N), VETA(N), VSIG(N)
! Size of local arrays: REAL(RP)*(4*N)
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : IK, RP, ONE, TENTH, DEBUGGING
use, non_intrinsic :: linalg_mod, only : matprod, isinv
use, non_intrinsic :: infnan_mod, only : is_nan, is_finite
use, non_intrinsic :: debug_mod, only : assert

implicit none

! Inputs
logical, intent(in) :: ximproved
real(RP), intent(in) :: d(:)    ! D(N)
real(RP), intent(in) :: delta
real(RP), intent(in) :: factor_alpha
real(RP), intent(in) :: factor_delta
real(RP), intent(in) :: sim(:, :)   ! SIM(N, N+1)
real(RP), intent(in) :: simi(:, :)  ! SIMI(N, N)

! Outputs
integer(IK) :: jdrop

! Local variables
character(len=*), parameter :: srname = 'SETDROP_TR'
integer(IK) :: n
logical :: mask(size(sim, 1))
real(RP) :: score(size(sim, 1) + 1)
real(RP) :: sigbar(size(sim, 1))
real(RP) :: simid(size(sim, 1))
real(RP) :: veta(size(sim, 1))
real(RP) :: vsig(size(sim, 1))
real(RP), parameter :: itol = TENTH

! Sizes
n = int(size(sim, 1), kind(n))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(size(d) == n .and. all(is_finite(d)), 'SIZE(D) == N, D is finite', srname)
    call assert(size(sim, 1) == n .and. size(sim, 2) == n + 1, 'SIZE(SIM) == [N, N+1]', srname)
    call assert(all(is_finite(sim)), 'SIM is finite', srname)
    call assert(all(maxval(abs(sim(:, 1:n)), dim=1) > 0), 'SIM(:, 1:N) has no zero column', srname)
    call assert(size(simi, 1) == n .and. size(simi, 2) == n, 'SIZE(SIMI) == [N, N]', srname)
    call assert(all(is_finite(simi)), 'SIMI is finite', srname)
    call assert(isinv(sim(:, 1:n), simi, itol), 'SIMI = SIM(:, 1:N)^{-1}', srname)
    call assert(factor_alpha > 0 .and. factor_alpha < 1, '0 < FACTOR_ALPHA < 1', srname)
    call assert(factor_delta > 1, 'FACTOR_DELTA > 1', srname)
end if

!====================!
! Calculation starts !
!====================!

! JDROP = 0 by default. It cannot be removed, as JDROP may not be set below in some cases (e.g.,
! when XIMPROVED == FALSE, MAXVAL(ABS(SIMID)) <= 1, and MAXVAL(VETA) <= EDGMAX).
jdrop = 0

simid = matprod(simi, d)
if (any(abs(simid) > 1) .or. (ximproved .and. any(.not. is_nan(simid)))) then
    jdrop = int(maxloc(abs(simid), mask=(.not. is_nan(simid)), dim=1), kind(jdrop))
    !!MATLAB: [~, jdrop] = max(simid, [], 'omitnan');
end if

if (ximproved) then
    veta = sqrt(sum((sim(:, 1:n) - spread(d, dim=2, ncopies=n))**2, dim=1))
    !!MATLAB: veta = sqrt(sum((sim(:, 1:n) - d).^2));  % d should be a column! Implicit expansion
else
    veta = sqrt(sum(sim(:, 1:n)**2, dim=1))
end if
vsig = ONE / sqrt(sum(simi**2, dim=2))
sigbar = abs(simid) * vsig
! The following JDROP will overwrite the previous one if its premise holds.
mask = (veta > factor_delta * delta .and. (sigbar >= factor_alpha * delta .or. sigbar >= vsig))
if (any(mask)) then
    jdrop = int(maxloc(veta, mask=mask, dim=1), kind(jdrop))
    !!MATLAB: etamax = max(veta(mask)); jdrop = find(mask & ~(veta < etamax), 1, 'first');
end if

! Powell's code does not include the following instructions. With Powell's code, if SIMID consists
! of only NaN, then JDROP can be 0 even when XIMPROVED == TRUE (i.e., D reduces the merit function).
! With the following code, JDROP cannot be 0 when XIMPROVED == TRUE, unless VETA is all NaN, which
! should not happen if X0 does not contain NaN, the trust-region/geometry steps never contain NaN,
! and we exit once encountering an iterate containing Inf (due to overflow).
if (ximproved .and. jdrop <= 0) then  ! Write JDROP <= 0 instead of JDROP == 0 for robustness.
    jdrop = int(maxloc(veta, mask=(.not. is_nan(veta)), dim=1), kind(jdrop))
    !!MATLAB: [~, jdrop] = max(veta, [], 'omitnan');
end if

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! New scheme
if (ximproved) then
    veta = (sum((sim(:, 1:n) - spread(d, dim=2, ncopies=n))**2, dim=1))
    !!MATLAB: veta = sqrt(sum((sim(:, 1:n) - d).^2));  % d should be a column! Implicit expansion
    score = [veta, sum(d**2)] * abs([simid, 1.0_RP - sum(simid)])
else
    veta = (sum(sim(:, 1:n)**2, dim=1))
    score = [veta, 0.0_RP] * abs([simid, 1.0_RP - sum(simid)])
end if

if (any(veta > 0)) then
    jdrop = maxloc(score, dim=1, mask=.not. is_nan(score))
elseif (ximproved) then
    jdrop = maxloc(veta, dim=1)
else
    jdrop = 0
end if


!====================!
!  Calculation ends  !
!====================!

! Postconditions
if (DEBUGGING) then
    !call assert(jdrop >= 0 .and. jdrop <= n, '0 <= JDROP <= N', srname)
    call assert(jdrop >= 1 .or. .not. ximproved, 'JDROP >= 1 unless the trust-region step failed', srname)
end if

end function setdrop_tr


function setdrop_geo(delta, factor_alpha, factor_beta, sim, simi) result(jdrop)
!--------------------------------------------------------------------------------------------------!
! This subroutine finds (the index) of a current interpolation point to be replaced by
! a geometry-improving point. See (15)--(16) of the COBYLA paper.
! N.B.: COBYLA never sets JDROP = N + 1.
!--------------------------------------------------------------------------------------------------!
! List of local arrays (including function-output arrays; likely to be stored on the stack):
! REAL(RP) :: VETA(N), VSIG(N)
! Size of local arrays: REAL(RP)*(2*N)
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : IK, RP, ONE, TENTH, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_nan, is_finite
use, non_intrinsic :: linalg_mod, only : isinv

implicit none

! Inputs
real(RP), intent(in) :: delta
real(RP), intent(in) :: factor_alpha
real(RP), intent(in) :: factor_beta
real(RP), intent(in) :: sim(:, :)   ! SIM(N, N+1)
real(RP), intent(in) :: simi(:, :)  ! SIMI(N, N)

! Outputs
integer(IK) :: jdrop

! Local variables
character(len=*), parameter :: srname = 'SETDROP_GEO'
integer(IK) :: n
real(RP) :: veta(size(sim, 1))
real(RP) :: vsig(size(sim, 1))
real(RP), parameter :: itol = TENTH

! Sizes
n = int(size(sim, 1), kind(n))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(size(sim, 1) == n .and. size(sim, 2) == n + 1, 'SIZE(SIM) == [N, N+1]', srname)
    call assert(all(is_finite(sim)), 'SIM is finite', srname)
    call assert(all(maxval(abs(sim(:, 1:n)), dim=1) > 0), 'SIM(:, 1:N) has no zero column', srname)
    call assert(size(simi, 1) == n .and. size(simi, 2) == n, 'SIZE(SIMI) == [N, N]', srname)
    call assert(all(is_finite(simi)), 'SIMI is finite', srname)
    call assert(isinv(sim(:, 1:n), simi, itol), 'SIMI = SIM(:, 1:N)^{-1}', srname)
    call assert(factor_alpha > 0 .and. factor_alpha < 1, '0 < FACTOR_ALPHA < 1', srname)
    call assert(factor_beta > 1, 'FACTOR_BETA > 1', srname)
end if

!====================!
! Calculation starts !
!====================!

! Calculate the values of sigma and eta.
! VSIG(J) (J=1, .., N) is the Euclidean distance from vertex J to the opposite face of the simplex.
vsig = ONE / sqrt(sum(simi**2, dim=2))
veta = sqrt(sum(sim(:, 1:n)**2, dim=1))

! Decide which vertex to drop from the simplex. It will be replaced by a new point to improve
! acceptability of the simplex. See equations (15) and (16) of the COBYLA paper.
if (any(veta > factor_beta * delta)) then
    jdrop = int(maxloc(veta, mask=(.not. is_nan(veta)), dim=1), kind(jdrop))
    !!MATLAB: [~, jdrop] = max(veta, [], 'omitnan');
elseif (any(vsig < factor_alpha * delta)) then
    jdrop = int(minloc(vsig, mask=(.not. is_nan(vsig)), dim=1), kind(jdrop))
    !!MATLAB: [~, jdrop] = min(vsig, [], 'omitnan');
else
    ! We arrive here if VSIG and VETA are all NaN, which can happen due to NaN in SIM and SIMI,
    ! which should not happen unless there is a bug.
    jdrop = 0
end if

!====================!
!  Calculation ends  !
!====================!

!Postconditions
if (DEBUGGING) then
    call assert(jdrop >= 1 .and. jdrop <= n, '1 <= JDROP <= N', srname)
end if
end function setdrop_geo


function geostep(jdrop, cpen, conmat, cval, delta, fval, factor_gamma, simi) result(d)
!--------------------------------------------------------------------------------------------------!
! This function calculates a geometry step so that the geometry of the interpolation set is improved
! when SIM(:, JDRO_GEO) is replaced by SIM(:, N+1) + D.
!--------------------------------------------------------------------------------------------------!
! List of local arrays (including function-output arrays; likely to be stored on the stack):
! REAL(RP) :: D(N), A(N, M+1)
! Size of local arrays: REAL(RP)*(N*(M+2)) (TO BE REDUCED: not pass SIMI and JDROP but SIMI_JDROP
! and A
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : IK, RP, ZERO, ONE, TWO, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_nan, is_finite, is_posinf, is_neginf
use, non_intrinsic :: linalg_mod, only : matprod, inprod, norm

implicit none

! Inputs
integer(IK), intent(in) :: jdrop
real(RP), intent(in) :: conmat(:, :)    ! CONMAT(M, N+1)
real(RP), intent(in) :: cpen
real(RP), intent(in) :: cval(:)     ! CVAL(N+1)
real(RP), intent(in) :: delta
real(RP), intent(in) :: factor_gamma
real(RP), intent(in) :: fval(:)     ! FVAL(N+1)
real(RP), intent(in) :: simi(:, :)  ! SIMI(N, N)

! Outputs
real(RP) :: d(size(simi, 1))  ! D(N)

! Local variables
character(len=*), parameter :: srname = 'GEOSTEP'
integer(IK) :: m
integer(IK) :: n
real(RP) :: A(size(simi, 1), size(conmat, 1) + 1)
real(RP) :: cvmaxn
real(RP) :: cvmaxp
real(RP) :: vsigj

! Sizes
m = int(size(conmat, 1), kind(m))
n = int(size(simi, 1), kind(m))

! Preconditions
if (DEBUGGING) then
    call assert(m >= 0, 'M >= 0', srname)
    call assert(n >= 1, 'N >= 1', srname)
    call assert(cpen >= 0, 'CPEN >= 0', srname)
    call assert(size(simi, 1) == n .and. size(simi, 2) == n, 'SIZE(SIMI) == [N, N]', srname)
    call assert(all(is_finite(simi)), 'SIMI is finite', srname)
    call assert(size(fval) == n + 1 .and. .not. any(is_nan(fval) .or. is_posinf(fval)), &
        & 'SIZE(FVAL) == NPT and FVAL is not NaN/+Inf', srname)
    call assert(size(conmat, 1) == m .and. size(conmat, 2) == n + 1, 'SIZE(CONMAT) == [M, N+1]', srname)
    call assert(.not. any(is_nan(conmat) .or. is_neginf(conmat)), 'CONMAT does not contain NaN/-Inf', srname)
    call assert(size(cval) == n + 1 .and. .not. any(cval < 0 .or. is_nan(cval) .or. is_posinf(cval)), &
        & 'SIZE(CVAL) == NPT and CVAL does not contain negative NaN/+Inf', srname)
    call assert(jdrop >= 1 .and. jdrop <= n, '1 <= JDROP <= N', srname)
    call assert(factor_gamma > 0 .and. factor_gamma < 1, '0 < FACTOR_GAMMA < 1', srname)
end if

!====================!
! Calculation starts !
!====================!

! SIMI(JDROP, :) is a vector perpendicular to the face of the simplex to the opposite of vertex
! JDROP. Thus VSIGJ * SIMI(JDROP, :) is the unit vector in this direction.
vsigj = ONE / sqrt(sum(simi(jdrop, :)**2))

! Set D to the vector in the above-mentioned direction and with length FACTOR_GAMMA * DELTA. Since
! FACTOR_ALPHA < FACTOR_GAMMA < FACTOR_BETA, D improves the geometry of the simplex as per (14) of
! the COBYLA paper. This also explains why this subroutine does not replace DELTA with
! DELBAR = MAX(MIN(TENTH * SQRT(MAXVAL(DISTSQ)), HALF * DELTA), RHO) as in NEWUOA.
d = factor_gamma * delta * (vsigj * simi(jdrop, :))

! Calculate the coefficients of the linear approximations to the objective and constraint functions,
! placing minus the objective function gradient after the constraint gradients in the array A.
A(:, 1:m) = transpose(matprod(conmat(:, 1:n) - spread(conmat(:, n + 1), dim=2, ncopies=n), simi))
!!MATLAB: A(:, 1:m) = simi'*(conmat(:, 1:n) - conmat(:, n+1))'; % Implicit expansion for subtraction
A(:, m + 1) = matprod(fval(n + 1) - fval(1:n), simi)
cvmaxp = maxval([ZERO, -matprod(d, A(:, 1:m)) - conmat(:, n + 1)])
cvmaxn = maxval([ZERO, matprod(d, A(:, 1:m)) - conmat(:, n + 1)])
if (TWO * inprod(d, A(:, m + 1)) < cpen * (cvmaxp - cvmaxn)) then
    d = -d
end if

!====================!
!  Calculation ends  !
!====================!

! Postconditions
if (DEBUGGING) then
    call assert(size(d) == n .and. all(is_finite(d)), 'SIZE(D) == N, D is finite', srname)
    ! In theory, |S| == FACTOR_GAMMA*DELTA, which may be false due to rounding, but not too far.
    ! It is crucial to ensure that the geometry step is nonzero, which holds in theory.
    call assert(norm(d) > 0.9_RP * factor_gamma * delta .and. norm(d) <= 1.1_RP * factor_gamma * delta, &
        & '|D| == FACTOR_GAMMA*DELTA', srname)
end if
end function geostep


end module geometry_mod
