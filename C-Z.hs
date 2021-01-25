module Algebra.Ring.Polynomial.Factorise
       ( -- * Factorisation
         factorise, factorQBigPrime, factorHensel,
         -- * Internal helper functions
         distinctDegFactor,
         equalDegreeSplitM, equalDegreeFactorM,
         henselStep, clearDenom,
         squareFreePart, squareFreeDecomp
       ) where
import Algebra.Algorithms.PrimeTest       hiding (modPow)
import Algebra.Field.Finite
import Algebra.Prelude.Core
import Algebra.Ring.Polynomial.Quotient
import Algebra.Ring.Polynomial.Univariate

import           Control.Applicative              ((<|>))
import           Control.Arrow                    ((***), (<<<))
import           Control.Lens                     (both, ifoldl, (%~), (&))
import           Control.Monad                    (guard, replicateM)
import           Control.Monad                    (when)
import           Control.Monad.Loops              (iterateUntil, untilJust)
import           Control.Monad.Random             (MonadRandom, uniform)
import           Control.Monad.ST.Strict          (ST, runST)
import           Control.Monad.Trans              (lift)
import           Control.Monad.Trans.Loop         (continue, foreach, while)
import qualified Data.DList                       as DL
import           Data.IntMap                      (IntMap)
import qualified Data.IntMap.Strict               as IM
import qualified Data.List                        as L
import           Data.Maybe                       (fromJust)
import           Data.Monoid                      (Sum (..))
import           Data.Monoid                      ((<>))
import           Data.Numbers.Primes              (primes)
import           Data.Proxy                       (Proxy (..))
import qualified Data.Set                         as S
import qualified Data.Sized.Builtin               as SV
import           Data.STRef.Strict                (STRef, modifySTRef, newSTRef)
import           Data.STRef.Strict                (readSTRef, writeSTRef)
import qualified Data.Traversable                 as F
import           Data.Type.Ordinal                (pattern OZ)
import qualified Data.Vector                      as V
import           Math.NumberTheory.Logarithms     (intLog2', integerLogBase')
import           Math.NumberTheory.Powers.Squares (integerSquareRoot)
import           Numeric.Decidable.Zero           (isZero)
import           Numeric.Domain.GCD               (gcd, lcm)
import qualified Numeric.Field.Fraction           as F
import qualified Prelude                          as P

-- | @distinctDegFactor f@ computes the distinct-degree decomposition of the given
--   square-free polynomial over finite field @f@.
distinctDegFactor :: forall k. (Eq k, FiniteField k)
                  => Unipol k     -- ^ Square-free polynomial over finite field.
                  -> [(Natural, Unipol k)]   -- ^ Distinct-degree decomposition.
distinctDegFactor f0 = zip [1..] $ go id (var OZ :: Unipol k) f0 []
  where
    go gs h f =
      let h' = modPow h (order (Proxy :: Proxy k)) f
          g' = gcd (h' - var 0) f
          f' = f `quot` g'
          gs' = gs . (g' :)
      in if f' == one
         then gs'
         else go gs' h' f'

modPow :: (Field (Coefficient poly), IsOrderedPolynomial poly)
       => poly -> Natural -> poly -> poly
modPow a p f = withQuotient (principalIdeal f) $
               repeatedSquare (modIdeal a) p

traceCharTwo :: (Unital m, Monoidal m) => Natural -> m -> m
traceCharTwo m a = sum [ a ^ (2 ^ i) | i <- [0..pred m]]

equalDegreeSplitM :: forall k m. (MonadRandom m, CoeffRing k,  FiniteField k)
                 => Unipol k
                 -> Natural
                 -> m (Maybe (Unipol k))
equalDegreeSplitM f d
  | fromIntegral (totalDegree' f) `mod` d /= 0 = return Nothing
  | otherwise = do
    let q = fromIntegral $ order (Proxy :: Proxy k)
        n = totalDegree' f
        els = elements (Proxy :: Proxy k)
    e <- uniform [1..n P.- 1]
    cs <- replicateM (fromIntegral e) $ uniform els
    let a = var 0 ^ fromIntegral e +
            sum (zipWith (*) (map injectCoeff cs) [var 0 ^ l | l <-[0..]])
        g1 = gcd a f
    return $ (guard (g1 /= one) >> return g1)
         <|> do let b | charUnipol f == 2  = traceCharTwo (powerUnipol f*d) a
                      | otherwise = modPow a ((pred $ q^d)`div`2) f
                    g2 = gcd (b - one) f
                guard (g2 /= one && g2 /= f)
                return g2

equalDegreeFactorM :: (Eq k, FiniteField k, MonadRandom m)
                   => Unipol k -> Natural -> m [Unipol k]
equalDegreeFactorM f d = go f >>= \a -> return (a [])
  where
    go h | totalDegree' h == 0 = return id
         | otherwise =
           if fromIntegral (totalDegree' h) == d
           then return (h:)
           else do
             g <- untilJust (equalDegreeSplitM h d)
             l <- go g
             r <- go (h `quot` g)
             return $ l . r

factorSquareFree :: (Eq k, FiniteField k, MonadRandom m)
                 => Unipol k -> m [Unipol k]
factorSquareFree f =
   concat <$> mapM (uncurry $ flip equalDegreeFactorM) (filter ((/= one) . snd) $ distinctDegFactor f)

squareFreePart :: (Eq k, FiniteField k)
               => Unipol k -> Unipol k
squareFreePart f =
  let !n = fromIntegral $ totalDegree' f
      u  = gcd f (diff 0 f)
      v  = f `quot` u
      f' = u `quot` gcd u (v ^ n)
  in if f' == one
     then v
     else v * squareFreePart (pthRoot f')

yun :: (CoeffRing r, Field r)
    => Unipol r -> IntMap (Unipol r)
yun f = let f' = diff OZ f
            u  = gcd f f'
        in go 1 IM.empty (f `quot` u) (f' `quot` u)
  where
    go !i dic v w =
      let t  = w - diff OZ v
          h  = gcd v t
          v' = v `quot` h
          w' = t `quot` h
          dic' = IM.insert i h dic
      in if v' == one
         then dic'
         else go (i+1) dic' v' w'

charUnipol :: forall r. Characteristic r => Unipol r -> Natural
charUnipol _ = char (Proxy :: Proxy r)

powerUnipol :: forall r. FiniteField r => Unipol r -> Natural
powerUnipol _ = power (Proxy :: Proxy r)

pthRoot :: (CoeffRing r, Characteristic r) => Unipol r -> Unipol r
pthRoot f =
  let !p = charUnipol f
  in if p == 0
     then error "char R should be positive prime"
     else mapMonomial (SV.map (`P.div` fromIntegral p)) f

squareFreeDecomp :: (Eq k, Characteristic k, Field k)
                 => Unipol k -> IntMap (Unipol k)
squareFreeDecomp f =
  let dcmp = yun f
      f'   = ifoldl (\i u g -> u `quot` (g ^ fromIntegral i)) f dcmp
      p    = fromIntegral $ charUnipol f
  in if charUnipol f == 0
     then dcmp
     else if isZero (f' - one)
     then dcmp
     else IM.filter (not . isZero . subtract one) $
          IM.unionWith (*) dcmp $ IM.mapKeys (p*) $ squareFreeDecomp $ pthRoot f'

-- | Factorise a polynomial over finite field using Cantor-Zassenhaus algorithm
factorise :: (MonadRandom m, CoeffRing k, FiniteField k)
          => Unipol k -> m [(Unipol k, Natural)]
factorise f = do
  concat <$> mapM (\(r, h) -> map (,fromIntegral r) <$> factorSquareFree h) (IM.toList $  squareFreeDecomp f)

clearDenom :: (CoeffRing a, Euclidean a)
           => Unipol (Fraction a) -> (a, Unipol a)
clearDenom f =
  let g = foldr (lcm . denominator) one $ terms' f
  in (g, mapCoeffUnipol (numerator . ((g F.% one)*)) f)
