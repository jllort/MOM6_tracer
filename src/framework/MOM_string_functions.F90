module MOM_string_functions
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
!*  By Alistair Adcroft and Robert Hallberg, last updated Sept. 2013.  *
!*                                                                     *
!*    The functions here perform a set of useful manipulations of      *
!*  character strings.   Although they are a part of MOM6, the do not  *
!*  require any other MOM software to be useful.                       *
!*                                                                     *
!********+*********+*********+*********+*********+*********+*********+**

implicit none ; private

public lowercase, uppercase
public left_int, left_ints
public left_real, left_reals
public stringFunctionsUnitTests
public extractWord
public slasher

contains

function lowercase(input_string)
!   This function returns a string in which all uppercase letters have been
! replaced by their lowercase counterparts.  It is loosely based on the
! lowercase function in mpp_util.F90.
  ! Arguments
  character(len=*),     intent(in) :: input_string
  character(len=len(input_string)) :: lowercase
  ! Local variables
  integer, parameter :: co=iachar('a')-iachar('A') ! case offset
  integer :: k

  lowercase = input_string
  do k=1, len_trim(input_string)
    if (lowercase(k:k) >= 'A' .and. lowercase(k:k) <= 'Z') &
        lowercase(k:k) = achar(ichar(lowercase(k:k))+co)
  end do
end function lowercase

function uppercase(input_string)
  character(len=*),     intent(in) :: input_string
  character(len=len(input_string)) :: uppercase
!   This function returns a string in which all lowercase letters have been
! replaced by their uppercase counterparts.  It is loosely based on the
! uppercase function in mpp_util.F90.
  ! Arguments
  integer, parameter :: co=iachar('A')-iachar('a') ! case offset
  integer :: k

  uppercase = input_string
  do k=1, len_trim(input_string)
    if (uppercase(k:k) >= 'a' .and. uppercase(k:k) <= 'z') &
        uppercase(k:k) = achar(ichar(uppercase(k:k))+co)
  end do
end function uppercase

function left_int(i)
! Returns a character string of a left-formatted integer
! e.g. "123       "  (assumes 19 digit maximum)
  ! Arguments
  character(len=19) :: left_int
  integer, intent(in) :: i
  ! Local variables
  character(len=19) :: tmp
  write(tmp(1:19),'(I19)') i
  write(left_int(1:19),'(A)') adjustl(tmp)
end function left_int

function left_ints(i)
! Returns a character string of a comma-separated, compact formatted,
! integers  e.g. "1, 2, 3, 4"
  ! Arguments
  character(len=1320) :: left_ints
  integer, intent(in) :: i(:)
  ! Local variables
  character(len=1320) :: tmp
  integer :: j
  write(left_ints(1:1320),'(A)') trim(left_int(i(1)))
  if (size(i)>1) then
    do j=2,size(i)
      tmp=left_ints
      write(left_ints(1:1320),'(A,", ",A)') trim(tmp),trim(left_int(i(j)))
    enddo
  endif
end function left_ints

function left_real(val)
  real, intent(in)  :: val
  character(len=32) :: left_real
! Returns a left-justified string with a real formatted like '(G)'
  integer :: l, ind

  if ((abs(val) < 1.0e4) .and. (abs(val) >= 1.0e-3)) then
    write(left_real, '(F30.11)') val
    if (.not.isFormattedFloatEqualTo(left_real,val)) then
      write(left_real, '(F30.12)') val
      if (.not.isFormattedFloatEqualTo(left_real,val)) then
        write(left_real, '(F30.13)') val
        if (.not.isFormattedFloatEqualTo(left_real,val)) then
          write(left_real, '(F30.14)') val
          if (.not.isFormattedFloatEqualTo(left_real,val)) then
            write(left_real, '(F30.15)') val
            if (.not.isFormattedFloatEqualTo(left_real,val)) then
              write(left_real, '(F30.16)') val
            endif
          endif
        endif
      endif
    endif
    do
      l = len_trim(left_real)
      if ((l<2) .or. (left_real(l-1:l) == ".0") .or. &
          (left_real(l:l) /= "0")) exit
      left_real(l:l) = " "
    enddo
  elseif (val == 0.) then
    left_real = "0.0"
  else
    write(left_real(1:32), '(ES23.14)') val
    if (.not.isFormattedFloatEqualTo(left_real,val)) then
     write(left_real(1:32), '(ES23.15)') val
    endif
    do
      ind = index(left_real,"0E")
      if (ind == 0) exit
      if (left_real(ind-1:ind-1) == ".") exit
      left_real = left_real(1:ind-1)//left_real(ind+1:)
    enddo
  endif
  left_real = adjustl(left_real)
end function left_real

function left_reals(r,sep)
! Returns a character string of a comma-separated, compact formatted, reals
! e.g. "1., 2., 5*3., 5.E2"
  ! Arguments
  character(len=1320) :: left_reals
  real, intent(in) :: r(:)
  character(len=*), optional :: sep
  ! Local variables
  integer :: j, n, b, ns
  logical :: doWrite
  character(len=10) :: separator
  n=1 ; doWrite=.true. ; left_reals='' ; b=1
  if (present(sep)) then
    separator=sep ; ns=len(sep)
  else
    separator=', ' ; ns=2
  endif
  do j=1,size(r)
    doWrite=.true.
    if (j<size(r)) then
      if (r(j)==r(j+1)) then
        n=n+1
        doWrite=.false.
      endif
    endif
    if (doWrite) then
      if (b>1) then ! Write separator if a number has already been written
        write(left_reals(b:),'(A)') separator
        b=b+ns
      endif
      if (n>1) then
        write(left_reals(b:),'(A,"*",A)') trim(left_int(n)),trim(left_real(r(j)))
      else
        write(left_reals(b:),'(A)') trim(left_real(r(j)))
      endif
      n=1 ; b=len_trim(left_reals)+1
    endif
  enddo
end function left_reals

function isFormattedFloatEqualTo(str, val)
! Returns True if the string can be read/parsed to give the exact
! value of "val"
  character(len=*), intent(in) :: str
  real,             intent(in) :: val
  logical                      :: isFormattedFloatEqualTo
  ! Local variables
  real :: scannedVal

  isFormattedFloatEqualTo=.false.
  read(str(1:),*,err=987) scannedVal
  if (scannedVal == val) isFormattedFloatEqualTo=.true.
 987 return
end function isFormattedFloatEqualTo

function extractWord(string,n)
! Returns string corresponding to the nth word in the argument
! or "" if the string is not long enough. Both spaces and commas
! are interpretted as separators.
  character(len=*), intent(in) :: string
  integer,          intent(in) :: n
  character(len=120) :: extractWord
  ! Local variables
  integer :: ns, i, b, e, nw
  logical :: lastCharIsSeperator
  extractWord = ''
  lastCharIsSeperator = .true.
  ns = len_trim(string)
  i = 0; b=0; e=0; nw=0;
  do while (i<ns)
    i = i+1
    if (lastCharIsSeperator) then ! search for end of word
      if (string(i:i)==' ' .or. string(i:i)==',') then
        continue ! Multiple separators, .e.g '  ' or ', '
      else
        lastCharIsSeperator = .false. ! character is beginning of word
        b = i
        continue
      endif
    else ! continue search for end of word
      if (string(i:i)==' ' .or. string(i:i)==',') then
        lastCharIsSeperator = .true.
        e = i-1 ! Previous character is end of word
        nw = nw+1
        if (nw==n) then
          extractWord = trim(string(b:e))
          return
        endif
      endif
    endif
  enddo
  if (b<=ns) extractWord = trim(string(b:ns))
end function extractWord

logical function stringFunctionsUnitTests()
  ! Should only be called from a single/root thread
  ! Returns True is a test fails, otherwise False
  integer :: i(5) = (/ -1, 1, 3, 3, 0 /)
  real :: r(8) = (/ 0., 1., -2., 1.3, 3.E-11, 3.E-11, 3.E-11, -5.1E12 /)
  stringFunctionsUnitTests = .false.
  write(*,*) '===== MOM_string_functions: stringFunctionsUnitTests ====='
  call localTest(left_int(i(1)),'-1')
  call localTest(left_ints(i(:)),'-1, 1, 3, 3, 0')
  call localTest(left_real(r(1)),'0.0')
  call localTest(left_reals(r(:)),'0.0, 1.0, -2.0, 1.3, 3*3.0E-11, -5.1E+12')
  call localTest(left_reals(r(:),sep=' '),'0.0 1.0 -2.0 1.3 3*3.0E-11 -5.1E+12')
  call localTest(left_reals(r(:),sep=','),'0.0,1.0,-2.0,1.3,3*3.0E-11,-5.1E+12')
  call localTest(extractWord("One Two,Three",1),"One")
  call localTest(extractWord("One Two,Three",2),"Two")
  call localTest(extractWord("One Two,Three",3),"Three")
  call localTest(extractWord("One Two,  Three",3),"Three")
  call localTest(extractWord(" One Two,Three",1),"One")
  write(*,*) '=========================================================='
  contains
  subroutine localTest(str1,str2)
    character(len=*) :: str1, str2
    write(*,*) '>'//trim(str1)//'<'
    if (trim(str1)/=trim(str2)) write(*,*) 'FAIL:',trim(str1),':',trim(str2)
    if (trim(str1)/=trim(str2)) stringFunctionsUnitTests=.true.
  end subroutine localTest
end function stringFunctionsUnitTests

function slasher(dir)
  character(len=*), intent(in) :: dir
  character(len=len(dir)+2) :: slasher

  if (len_trim(dir) == 0) then
    slasher = "./"
  elseif (dir(len_trim(dir):len_trim(dir)) == '/') then
    slasher = trim(dir)
  else
    slasher = trim(dir)//"/"
  endif
end function slasher

end module MOM_string_functions
