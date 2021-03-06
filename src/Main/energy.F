      SUBROUTINE ENERGY(iscale)
*
*
*       Total energy.
*       -------------
*
      INCLUDE 'common6.h'
      COMMON/POTDEN/  RHO(NMAX),XNDBL(NMAX),PHIDBL(NMAX)
      logical iscale
*
*
*       Sum the total energy of regularized pairs.
      if(.not.iscale) then
         EBIN = 0.0D0
         DO 10 IPAIR = 1,NPAIRS
*     Skip pairs with zero mass of c.m. particle (merged binary ghost).
            IF (BODY(N+IPAIR).GT.0.0D0) THEN
*     Predict coordinates, velocities & binding energy.
               CALL RESOLV(IPAIR,1)
               EBIN = EBIN + BODY(2*IPAIR-1)*BODY(2*IPAIR)*HT/
     &              BODY(N+IPAIR)
            END IF
 10      CONTINUE
      end if
*
*       Calculate the potential energy.
      ZKIN = 0.D00
      POT = 0.0
#ifdef GPU
*     Use GPU to get potential
      NNT = NTOT - IFIRST + 1
      CALL GPUPOT(rank,1,NNT,NNT,BODY(IFIRST),X(1,IFIRST)
     &     ,phidbl(ifirst))

*       Move the table entries down to give room for any KS components.
      I2 = 2*NPAIRS
      IF (NPAIRS.GT.0) THEN
*       Copy c.m. potential to the components.
          DO IPAIR = 1,NPAIRS
              I1 = 2*IPAIR - 1
              PHIDBL(I1) = PHIDBL(N+IPAIR)
              PHIDBL(I1+1) = PHIDBL(N+IPAIR)
           END DO
      END IF

*       Sum individual contributions after differential correction.
      DO 20 I = IFIRST,NTOT
          CALL PHICOR(I,DPHI1,DPHI2)
          IF (I.LE.N) THEN
              PHIDBL(I) = PHIDBL(I) + DPHI1
              POT = POT + BODY(I)*PHIDBL(I)
          ELSE
              I1 = 2*(I - N) - 1
              PHIDBL(I1) = PHIDBL(I1) + DPHI1
              PHIDBL(I1+1) = PHIDBL(I1+1) + DPHI2
              POT = POT + BODY(I1)*PHIDBL(I1) + BODY(I1+1)*PHIDBL(I1+1)
          END IF
   20 CONTINUE
*
*       Take half the value because of double counting.
      POT = 0.5*POT

#else
!$omp parallel do private(I,JMIN,IPAIR,POTI,POTJ,A1,A2,A3,A4) 
!$omp& reduction(+:POT)
      DO 20 I = 1,NTOT
         JMIN = I + 1
         IF (I.LE.2*NPAIRS) THEN
*     Binding energy of regularized pairs is included explicitly above.
            IPAIR = KVEC(I)
            JMIN = 2*IPAIR + 1
         END IF
*     
         IPAIR = 0
         IF (I.GT.N)  THEN
*     Binding energy at center of mass position without binary members
            IPAIR = I - N
         END IF
*     
         POTJ = 0.D00
         POTI = 0.D00
*     POTI contains potential at particles position to be stored later (R.Sp.)
         DO 30 J = 1,N
            IF (J.EQ.I .OR. J.EQ.2*IPAIR-1 .OR. J.EQ.2*IPAIR .OR.
     *           BODY(J).EQ.0.0D0 .OR. BODY(I).EQ.0.0D0)  GO TO 30
            A1 = X(1,I) - X(1,J)
            A2 = X(2,I) - X(2,J)
            A3 = X(3,I) - X(3,J)
            A4 = BODY(J)/DSQRT (A1*A1 + A2*A2 + A3*A3)
            POTI = POTI - A4
*     also J.LT.N?
            IF(J.GE.JMIN)POTJ = POTJ + A4
 30      CONTINUE
*     Store potential in shared vector first (R.Sp.)
         PHIDBL(I) = -POTI
         POT = POT + BODY(I)*POTJ
   20 CONTINUE
!$omp end parallel do
#endif

*
*       Sum the kinetic energy (include c.m. bodies but not components).
      DO 40 I = IFIRST,NTOT
          ZKIN = ZKIN + BODY(I)*(XDOT(1,I)**2 + XDOT(2,I)**2 +
     &                                          XDOT(3,I)**2)
   40 CONTINUE
      ZKIN = 0.5D0*ZKIN
*
*       Obtain the tidal potential energy for linearized external field. 
      IF (KZ(14).EQ.0) THEN
*       Note: EPL holds accumulated tidal energy if KZ(14) = 3.
          EPL = 0.0D0
      ELSE
*       Employ general expression sum {m*r*F} for virial energy.
          CALL XTRNLV(1,N)
*       Form tidal energy with Plummer potential (note EPL use for #14=3).
          IF (KZ(14).EQ.3.OR.KZ(14).EQ.4) THEN
              EPL = 0.0
              DO 50 I = 1,N
                  RI2 = AP2
                  DO 45 K = 1,3
                      RI2 = RI2 + X(K,I)**2
   45             CONTINUE
                  EPL = EPL - BODY(I)*MP/SQRT(RI2)
   50         CONTINUE
          END IF
      END IF
*
*       Check differential potential energy due to chain subsystem.
      IF (NCH.GT.0) THEN
          CALL CHPOT(DP)
          POT = POT + DP
      END IF
*
*       Total energy = ZKIN - POT + EPL + EBIN + ESUB + EMERGE + ECOLL.
*
      RETURN
*
      END
