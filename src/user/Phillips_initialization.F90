module Phillips_initialization
!***********************************************************************
!*                   GNU General Public License                        *
!* This file is a part of MOM.                                         *
!*                                                                     *
!* MOM is free software; you can redistribute it and/or modify it and  *
!* are expected to follow the terms of the GNU General Public License  *
!* as published by the Free Software Foundation; either version 2 of   *
!* the License, or (at your option) any later version.                 *
!*                                                                     *
!* MOM is distributed in the hope that it will be useful, but WITHOUT  *
!* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY  *
!* or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public    *
!* License for more details.                                           *
!*                                                                     *
!* For the full text of the GNU General Public License,                *
!* write to: Free Software Foundation, Inc.,                           *
!*           675 Mass Ave, Cambridge, MA 02139, USA.                   *
!* or see:   http://www.gnu.org/licenses/gpl.html                      *
!***********************************************************************

!********+*********+*********+*********+*********+*********+*********+**
!*                                                                     *
!*  By Robert Hallberg, April 1994 - June 2002                         *
!*                                                                     *
!*    This subroutine initializes the fields for the simulations.      *
!*  The one argument passed to initialize, Time, is set to the         *
!*  current time of the simulation.  The fields which are initialized  *
!*  here are:                                                          *
!*    u - Zonal velocity in m s-1.                                     *
!*    v - Meridional velocity in m s-1.                                *
!*    h - Layer thickness in m.  (Must be positive.)                   *
!*    D - Basin depth in m.  (Must be positive.)                       *
!*    f - The Coriolis parameter, in s-1.                              *
!*    g - The reduced gravity at each interface, in m s-2.             *
!*    Rlay - Layer potential density (coordinate variable) in kg m-3.  *
!*  If ENABLE_THERMODYNAMICS is defined:                               *
!*    T - Temperature in C.                                            *
!*    S - Salinity in psu.                                             *
!*  If SPONGE is defined:                                              *
!*    A series of subroutine calls are made to set up the damping      *
!*    rates and reference profiles for all variables that are damped   *
!*    in the sponge.                                                   *
!*  Any user provided tracer code is also first linked through this    *
!*  subroutine.                                                        *
!*                                                                     *
!*    Forcing-related fields (taux, tauy, buoy, ustar, etc.) are set   *
!*  in MOM_surface_forcing.F90.                                        *
!*                                                                     *
!*    These variables are all set in the set of subroutines (in this   *
!*  file) USER_initialize_bottom_depth, USER_initialize_thickness,     *
!*  USER_initialize_velocity,  USER_initialize_temperature_salinity,   *
!*  USER_initialize_mixed_layer_density, USER_initialize_sponges,      *
!*  USER_set_coord, and USER_set_ref_profile.                          *
!*                                                                     *
!*    The names of these subroutines should be self-explanatory. They  *
!*  start with "USER_" to indicate that they will likely have to be    *
!*  modified for each simulation to set the initial conditions and     *
!*  boundary conditions.  Most of these take two arguments: an integer *
!*  argument specifying whether the fields are to be calculated        *
!*  internally or read from a NetCDF file; and a string giving the     *
!*  path to that file.  If the field is initialized internally, the    *
!*  path is ignored.                                                   *
!*                                                                     *
!*  Macros written all in capital letters are defined in MOM_memory.h. *
!*                                                                     *
!*     A small fragment of the grid is shown below:                    *
!*                                                                     *
!*    j+1  x ^ x ^ x   At x:  q, f                                     *
!*    j+1  > o > o >   At ^:  v, tauy                                  *
!*    j    x ^ x ^ x   At >:  u, taux                                  *
!*    j    > o > o >   At o:  h, D, buoy, tr, T, S, ustar              *
!*    j-1  x ^ x ^ x                                                   *
!*        i-1  i  i+1  At x & ^:                                       *
!*           i  i+1    At > & o:                                       *
!*                                                                     *
!*  The boundaries always run through q grid points (x).               *
!*                                                                     *
!********+*********+*********+*********+*********+*********+*********+**

use MOM_error_handler, only : MOM_mesg, MOM_error, FATAL, is_root_pe
use MOM_file_parser, only : get_param, log_version, param_file_type
use MOM_get_input, only : directories
use MOM_grid, only : ocean_grid_type
use MOM_io, only : close_file, create_file, fieldtype, file_exists
use MOM_io, only : open_file, read_data, read_axis_data, SINGLE_FILE
use MOM_io, only : write_field, slasher
use MOM_sponge, only : set_up_sponge_field, initialize_sponge, sponge_CS
use MOM_tracer_registry, only : tracer_registry_type, add_tracer_OBC_values
use MOM_variables, only : thermo_var_ptrs
use MOM_variables, only : ocean_OBC_type, OBC_NONE, OBC_SIMPLE
use MOM_variables, only : OBC_FLATHER_E, OBC_FLATHER_W, OBC_FLATHER_N, OBC_FLATHER_S
use MOM_EOS, only : calculate_density, calculate_density_derivs, EOS_type
implicit none ; private

#include <MOM_memory.h>

public Phillips_initialize_thickness
public Phillips_initialize_velocity
public Phillips_initialize_sponges

! This include declares and sets the variable "version".
#include "version_variable.h"

contains

subroutine Phillips_initialize_thickness(h, G, param_file)
  real, intent(out), dimension(NIMEM_,NJMEM_, NKMEM_) :: h
  type(ocean_grid_type), intent(in) :: G
  type(param_file_type), intent(in) :: param_file

  real :: eta0(SZK_(G)+1)   ! The 1-d nominal positions of the interfaces.
  real :: eta_im(SZJ_(G),SZK_(G)+1) ! A temporary array for zonal-mean eta, m.
  real :: eta1D(SZK_(G)+1)  ! Interface height relative to the sea surface
                            ! positive upward, in m.
  real :: damp_rate, jet_width, jet_height, y_2
  real :: half_strat, half_depth
  character(len=40)  :: mod = "USER_initialize_sponges" ! This subroutine's name.
  integer :: i, j, k, is, ie, js, je, isd, ied, jsd, jed, nz

  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = G%ke
  isd = G%isd ; ied = G%ied ; jsd = G%jsd ; jed = G%jed
  
  eta_im(:,:) = 0.0

  call log_version(param_file, mod, version)
  call get_param(param_file, mod, "HALF_STRAT_DEPTH", half_strat, &
                 "The maximum depth of the ocean.", units="nondim", &
                 default = 0.5)
  call get_param(param_file, mod, "JET_WIDTH", jet_width, &
                 "The width of the zonal-mean jet.", units="km", &
                 fail_if_missing=.true.)
  call get_param(param_file, mod, "JET_HEIGHT", jet_height, &
                 "The interface height scale associated with the \n"//&
                 "zonal-mean jet.", units="m", &
                 fail_if_missing=.true.)

  half_depth = G%max_depth*half_strat
  eta0(1) = 0.0 ; eta0(nz+1) = -G%max_depth
  do k=2,1+nz/2 ; eta0(k) = -half_depth*(2.0*(k-1)/real(nz)) ; enddo
  do k=2+nz/2,nz+1
    eta0(k) = -G%max_depth - 2.0*(G%max_depth-half_depth) * ((k-(nz+1))/real(nz))
  enddo

  do j=js,je
    eta_im(j,1) = 0.0 ; eta_im(j,nz+1) = -G%max_depth
  enddo
  do K=2,nz ; do j=js,je
    y_2 = G%geoLatT(is,j) - G%south_lat - 0.5*G%len_lat
    eta_im(j,K) = eta0(k) + &
         jet_height * tanh(y_2 / jet_width)
!         jet_height * atan(y_2 / jet_width)
    if (eta_im(j,K) > 0.0) eta_im(j,K) = 0.0
    if (eta_im(j,K) < -G%max_depth) eta_im(j,K) = -G%max_depth
  enddo ; enddo

  do j=js,je ; do i=is,ie
!    This sets the initial thickness (in m) of the layers.  The      !
!  thicknesses are set to insure that: 1.  each layer is at least an !
!  Angstrom thick, and 2.  the interfaces are where they should be   !
!  based on the resting depths and interface height perturbations,   !
!  as long at this doesn't interfere with 1.                         !
    eta1D(nz+1) = -1.0*G%bathyT(i,j)
    do k=nz,1,-1
      eta1D(K) = eta_im(j,K)
      if (eta1D(K) < (eta1D(K+1) + G%Angstrom_z)) then
        eta1D(K) = eta1D(K+1) + G%Angstrom_z
        h(i,j,k) = G%Angstrom_z
      else
        h(i,j,k) = eta1D(K) - eta1D(K+1)
      endif
    enddo
  enddo ; enddo

end subroutine Phillips_initialize_thickness

subroutine Phillips_initialize_velocity(u, v, G, param_file)
  real, dimension(NIMEMB_,NJMEM_, NKMEM_), intent(out) :: u
  real, dimension(NIMEM_,NJMEMB_, NKMEM_), intent(out) :: v
  type(ocean_grid_type),                intent(in)  :: G
  type(param_file_type),                intent(in)  :: param_file

  real :: damp_rate, jet_width, jet_height, x_2, y_2
  real :: velocity_amplitude, pi
  integer :: i, j, k, is, ie, js, je, nz, m
  character(len=40)  :: mod = "Phillips_initialize_velocity" ! This subroutine's name.
  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = G%ke

  u(:,:,:) = 0.0
  v(:,:,:) = 0.0

  pi = 4.0*atan(1.0)

  call log_version(param_file, mod, version)
  call get_param(param_file, mod, "VELOCITY_IC_PERTURB_AMP", velocity_amplitude, &
                 "The magnitude of the initial velocity perturbation.", &
                 units="m s-1", default=0.001)
  call get_param(param_file, mod, "JET_WIDTH", jet_width, &
                 "The width of the zonal-mean jet.", units="km", &
                 fail_if_missing=.true.)
  call get_param(param_file, mod, "JET_HEIGHT", jet_height, &
                 "The interface height scale associated with the \n"//&
                 "zonal-mean jet.", units="m", &
                 fail_if_missing=.true.)

  ! Use thermal wind shear to give a geostrophically balanced flow.
  do k=nz-1,1 ; do j=js,je ; do I=is-1,ie
    y_2 = G%geoLatCu(I,j) - G%south_lat - 0.5*G%len_lat
! This uses d/d y_2 atan(y_2 / jet_width)
!    u(I,j,k) = u(i,j,k+1) + (1e-3 * jet_height / &
!           (jet_width * (1.0 + (y_2 / jet_width)**2))) * &
!           (2.0 * G%g_prime(K+1) / (G%CoriolisBu(I,J) + G%CoriolisBu(I,J-1)))
! This uses d/d y_2 tanh(y_2 / jet_width)
    u(I,j,k) = u(i,j,k+1) + (1e-3 * (jet_height / jet_width) * &
           (sech(y_2 / jet_width))**2 ) * &
           (2.0 * G%g_prime(K+1) / (G%CoriolisBu(I,J) + G%CoriolisBu(I,J-1)))
  enddo ; enddo ; enddo

  do k=1,nz ; do j=js,je ; do I=is-1,ie
    y_2 = (G%geoLatCu(I,j) - G%south_lat - 0.5*G%len_lat) / G%len_lat
    x_2 = (G%geoLonCu(I,j) - G%west_lon - 0.5*G%len_lon) / G%len_lon
    u(i,j,k) = u(i,j,k) + velocity_amplitude * ((real(k)-0.5)/real(nz)) * &
           (0.5 - abs(2.0*x_2) + 0.1*abs(cos(10.0*pi*x_2)) - abs(sin(5.0*pi*y_2)))
    do m=1,10
      u(i,j,k) = u(i,j,k) + 0.2*velocity_amplitude * ((real(k)-0.5)/real(nz)) * &
            cos(2.0*m*pi*x_2 + 2*m) * cos(6.0*pi*y_2)
    enddo
  enddo ; enddo ; enddo

end subroutine Phillips_initialize_velocity

subroutine Phillips_initialize_sponges(G, use_temperature, tv, param_file, CSp, h)
  type(ocean_grid_type), intent(in) :: G
  logical, intent(in) :: use_temperature
  type(thermo_var_ptrs), intent(in) :: tv
  type(param_file_type), intent(in) :: param_file
  type(sponge_CS),       pointer    :: CSp
  real, intent(in), dimension(NIMEM_,NJMEM_, NKMEM_) :: h

  real :: eta0(SZK_(G)+1)   ! The 1-d nominal positions of the interfaces.
  real :: eta(SZI_(G),SZJ_(G),SZK_(G)+1) ! A temporary array for eta, m.
  real :: temp(SZI_(G),SZJ_(G),SZK_(G))  ! A temporary array for other variables. !
  real :: Idamp(SZI_(G),SZJ_(G))    ! The inverse damping rate, in s-1.
  real :: eta_im(SZJ_(G),SZK_(G)+1) ! A temporary array for zonal-mean eta, m.
  real :: Idamp_im(SZJ_(G))         ! The inverse zonal-mean damping rate, in s-1.
  real :: damp_rate, jet_width, jet_height, y_2
  real :: half_strat, half_depth
  character(len=40)  :: mod = "Phillips_initialize_sponges" ! This subroutine's name.

  integer :: i, j, k, is, ie, js, je, isd, ied, jsd, jed, nz
  logical, save :: first_call = .true.

  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = G%ke
  isd = G%isd ; ied = G%ied ; jsd = G%jsd ; jed = G%jed
  
  eta(:,:,:) = 0.0 ; temp(:,:,:) = 0.0 ; Idamp(:,:) = 0.0
  eta_im(:,:) = 0.0 ; Idamp_im(:) = 0.0

  if (first_call) call log_version(param_file, mod, version)
  first_call = .false.
  call get_param(param_file, mod, "HALF_STRAT_DEPTH", half_strat, &
                 "The maximum depth of the ocean.", units="nondim", &
                 default = 0.5)
  call get_param(param_file, mod, "SPONGE_RATE", damp_rate, &
                 "The rate at which the zonal-mean sponges damp.", units="s-1", &
                 default = 1.0/(10.0*86400.0))

  call get_param(param_file, mod, "JET_WIDTH", jet_width, &
                 "The width of the zonal-mean jet.", units="km", &
                 fail_if_missing=.true.)
  call get_param(param_file, mod, "JET_HEIGHT", jet_height, &
                 "The interface height scale associated with the \n"//&
                 "zonal-mean jet.", units="m", &
                 fail_if_missing=.true.)

  half_depth = G%max_depth*half_strat
  eta0(1) = 0.0 ; eta0(nz+1) = -G%max_depth
  do k=2,1+nz/2 ; eta0(k) = -half_depth*(2.0*(k-1)/real(nz)) ; enddo
  do k=2+nz/2,nz+1
    eta0(k) = -G%max_depth - 2.0*(G%max_depth-half_depth) * ((k-(nz+1))/real(nz))
  enddo

  do j=js,je
    Idamp_im(j) = damp_rate
    eta_im(j,1) = 0.0 ; eta_im(j,nz+1) = -G%max_depth
  enddo
  do K=2,nz ; do j=js,je
    y_2 = G%geoLatT(is,j) - G%south_lat - 0.5*G%len_lat
    eta_im(j,K) = eta0(k) + &
         jet_height * tanh(y_2 / jet_width)
!         jet_height * atan(y_2 / jet_width)
    if (eta_im(j,K) > 0.0) eta_im(j,K) = 0.0
    if (eta_im(j,K) < -G%max_depth) eta_im(j,K) = -G%max_depth
  enddo ; enddo

  call initialize_sponge(Idamp, eta, G, param_file, CSp, Idamp_im, eta_im)

end subroutine Phillips_initialize_sponges

function sech(x)
  real, intent(in) :: x
  real             :: sech
  ! sech calculates the hyperbolic secant.
  
  ! This is here to prevent overflows or underflows.
  if (abs(x) > 228.) then
    sech = 0.0
  else
    sech = 2.0 / (exp(x) + exp(-x))
  endif
end function sech

end module Phillips_initialization
