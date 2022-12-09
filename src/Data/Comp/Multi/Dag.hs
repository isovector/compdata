{-# LANGUAGE BangPatterns         #-}
{-# LANGUAGE DeriveDataTypeable   #-}
{-# LANGUAGE DoAndIfThenElse      #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE RecursiveDo          #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE TypeSynonymInstances #-}


--------------------------------------------------------------------------------
-- |
-- Module      :  Data.Comp.Dag
-- Copyright   :  (c) 2014 Patrick Bahr, Emil Axelsson
-- License     :  BSD3
-- Maintainer  :  Patrick Bahr <paba@di.ku.dk>
-- Stability   :  experimental
-- Portability :  non-portable (GHC Extensions)
--
-- This module implements a representation of directed acyclic graphs
-- (DAGs) as compact representations of trees (or 'Term's).
--
--------------------------------------------------------------------------------

module Data.Comp.Multi.Dag
    ( Dag
    , termTree
    --, reifyDag
    --, unravel
    --, bisim
    --, iso
    --, strongIso
    ) where

import Control.Exception.Base
import Control.Monad.State
import Data.Comp.Multi.Dag.Internal
import Data.Comp.Multi.Equality
import Data.Comp.Multi.Term
import Data.Comp.Multi.HFunctor
import Data.Comp.Multi.HFoldable (HFoldable)
import qualified Data.Dependent.HashMap as DH
--import Data.IntMap
--import qualified Data.IntMap as IntMap
import Data.IORef
import Data.Comp.Multi.HTraversable
import qualified Data.Traversable as Traversable
import Data.Typeable
import System.Mem.StableName

import Control.Monad.ST
import Data.Comp.Multi.Show
import Data.Comp.Multi.HTraversable
import Data.List
import Data.STRef
import Data.Some
import Data.Hashable
import qualified Data.Vector as Vec
import qualified Data.Vector.Generic.Mutable as MVec
import qualified Data.Dependent.Map as M
import qualified Data.Dependent.Sum as S
import Unsafe.Coerce

instance Show (Node a) where
    show (K i) = show i

type IntMap = M.DMap Node

instance (ShowHF f, HFunctor f) => Show (Dag f i)
  where
    show (Dag r es _) = unwords
        [ "mkDag"
        , show  (Term r)
        , showLst ["(" ++ show n ++ "," ++ show (Term f) ++ ")" | (n S.:=>f) <- M.toList es ]
        ]
      where
        showLst ss = "[" ++ intercalate "," ss ++ "]"


-- | Turn a term into a graph without sharing.
termTree :: HFunctor f => Term f :-> Dag f
termTree (Term t) = Dag (hfmap toCxt t) M.empty 0

-- | This exception indicates that a 'Term' could not be reified to a
-- 'Dag' (using 'reifyDag') due to its cyclic sharing structure.
data CyclicException = CyclicException
    deriving (Show, Typeable)

instance Exception CyclicException

newtype SName f i = SName {getSName :: StableName (f (Term f) i)}
instance Hashable (SName f i) where
    hashWithSalt i = hashWithSalt 239 . hashWithSalt i . getSName
instance Hashable (Some (SName f)) where
    hashWithSalt i (Some x) = hashWithSalt 890 $ hashWithSalt i x
newtype TermPair f i = TermPair {getTermPair :: (Bool, StableName (f (Term f) i))}
    {-

-- | This function takes a term, and returns a 'Dag' with the implicit
-- sharing of the input data structure made explicit. If the sharing
-- structure of the term is cyclic an exception of type
-- 'CyclicException' is thrown.
reifyDag :: HTraversable f => NatM IO (Term f) (Dag f)
reifyDag m = mdo
  tabRef <- newIORef DH.empty
  let _ = findNodes :: Term f i -> IO (Some (SName f))
  let findNodes (Term !j) = do
        st <- liftIO $ makeStableName j
        let stKey = SName st
        tab <- readIORef tabRef
        case DH.lookup stKey tab of
          Just (TermPair (single,f)) | single -> writeIORef tabRef (DH.insert stKey (TermPair (False,f)) tab)
                                      >> return stKey
                          | otherwise -> return stKey
          Nothing -> do _res <- hmapM findNodes j
                        tab <- readIORef tabRef
                        if DH.member stKey tab
                          then throwIO CyclicException
                          else writeIORef tabRef (DH.insert stKey (TermPair (True, unsafeCoerce res)) tab)
                               >> return stKey
  st <- findNodes m
  tab <- readIORef tabRef
  counterRef :: IORef Int <- newIORef 0
  edgesRef <- newIORef M.empty
  nodesRef <- newIORef DH.empty
  let _ = run :: Some (SName f) -> IO (Some (Context f (K Int)))
  let run (Some st) = do
        let stKey = SName st
        let TermPair (single,f) = tab DH.! stKey
        if single then Term <$> hmapM run f
        else do
          nodes <- readIORef nodesRef
          case DH.lookup st nodes of
            Just n -> return (Hole $ K n)
            Nothing -> do
              n <- readIORef counterRef
              writeIORef counterRef $! (n+1)
              writeIORef nodesRef (DH.insert st (K n) nodes)
              f' <- hmapM run f
              modifyIORef edgesRef (M.insert (K n) f')
              return (Hole . K $ K n)
  Term root <- run st
  edges <- readIORef edgesRef
  count <- readIORef counterRef
  return (Dag (unsafeCoerce root) edges count)


-- | This function unravels a given graph to the term it
-- represents.

unravel :: forall f. HFunctor f => Dag f :-> Term f
unravel Dag {edges, root} = Term $ build <$> root
    where build :: forall i . Context f Node i -> Term f i
          build (Term t) = Term $ build <$> t
          build (Hole n) = Term $ build <$> edges M.! n

-- | Checks whether two dags are bisimilar. In particular, we have
-- the following equality
--
-- @
-- bisim g1 g2 = (unravel g1 == unravel g2)
-- @
--
-- That is, two dags are bisimilar iff they have the same unravelling.

bisim :: forall f . (EqHF f, HFunctor f, HFoldable f)  => Dag f :=> Dag f :=> Bool
bisim Dag {root=r1,edges=e1}  Dag {root=r2,edges=e2} = runF r1 r2
    where run :: forall i . (Context f Node i, Context f Node i) -> Bool
          run (t1, t2) = runF (step e1 t1) (step e2 t2)
          step :: Edges f -> Context f Node i -> f (Context f Node) i
          step e (Hole n) = e IntMap.! n
          step _ (Term t) = t
          runF :: forall i . f (Context f Node) i -> f (Context f Node) i -> Bool
          runF f1 f2 = case eqMod f1 f2 of
                         Nothing -> False
                         Just l -> all run l


-- | Checks whether the two given DAGs are isomorphic.

iso :: (HTraversable f, HFoldable f, EqHF f) => Dag f :=> Dag f :=> Bool
iso g1 g2 = checkIso eqMod (flatten g1) (flatten g2)


-- | Checks whether the two given DAGs are strongly isomorphic, i.e.
--   their internal representation is the same modulo renaming of
--   nodes.

strongIso :: (HFunctor f, HFoldable f, EqHF f) => Dag f :=> Dag f :=> Bool
strongIso Dag {root=r1,edges=e1,nodeCount=nx1}
          Dag {root=r2,edges=e2,nodeCount=nx2}
              = checkIso checkEq (r1,e1,nx1) (r2,e2,nx2)
    where checkEq t1 t2 = eqMod (Term t1) (Term t2)



-- | This function flattens the internal representation of a DAG. That
-- is, it turns the nested representation of edges into single layers.

flatten :: forall f . HTraversable f => forall i . Dag f i -> (f Node i, M.DMap Node (f Node), Int)
flatten Dag {root,edges,nodeCount} = runST run where
    run :: forall s i . ST s (f Node i, M.DMap Node (f Node), Int)
    run = do
      count <- newSTRef 0
      nMap :: Vec.MVector s (Maybe (Node i)) <- MVec.new nodeCount
      MVec.set nMap Nothing
      newEdges <- newSTRef M.empty
      let build :: Context f Node i -> ST s (Node i)
          build (Hole n) = mkNode (unK n)
          build (Term t) = do
            n' <- readSTRef count
            writeSTRef count $! (n'+1)
            t' <- hmapM build t
            modifySTRef newEdges (M.insert n' t')
            return n'
          mkNode n = do
            mn' <- MVec.unsafeRead nMap n
            case mn' of
              Just n' -> return n'
              Nothing -> do n' <- readSTRef count
                            writeSTRef count $! (n'+1)
                            MVec.unsafeWrite nMap n (Just n')
                            return n'
          buildF (n,t) = do
            n' <- mkNode n
            t' <- Traversable.mapM build t
            modifySTRef newEdges (M.insert n' t')
      root' <- Traversable.mapM build root
      mapM_ buildF $ M.toList edges
      edges' <- readSTRef newEdges
      nodeCount' <- readSTRef count
      return (root', edges', nodeCount')


     -}

-- | Checks whether the two given dag representations are
-- isomorphic. This function is polymorphic in the representation of
-- the edges. The first argument is a function that checks whether two
-- edges have the same labelling and if so, returns the matching pairs
-- of outgoing nodes the two edges point to. Otherwise the function
-- returns 'Nothing'.

checkIso :: (e i -> e i -> Maybe [(Node i,Node i)])
         -> (e i, M.DMap Node e, Int)
         -> (e i, M.DMap Node e, Int) -> Bool
checkIso checkEq (r1,e1,nx1) (r2,e2,nx2) = runST run where
   run :: ST s Bool
   run = do
     -- create empty mapping from nodes in g1 to nodes in g2
     nMap :: Vec.MVector s (Maybe (Node j)) <- MVec.new nx1
     MVec.set nMap Nothing
     -- create empty set of nodes in g2 that are "mapped to" by the
     -- mapping created above
     nSet :: Vec.MVector s Bool <- MVec.new nx2
     MVec.set nSet False
     let checkT t1 t2 = case checkEq t1 t2 of
                          Nothing -> return False
                          Just l -> liftM and $ mapM checkN l
         checkN (n1,n2) = do
           nm' <- MVec.unsafeRead nMap (unK n1)
           case nm' of
             Just n' -> return (n2 == n')
             _ -> do
               b <- MVec.unsafeRead nSet (unK n2)
               if b
               -- n2 is already mapped to by another node
               then return False
               -- n2 is not mapped to
               else do
                 -- create mapping from n1 to n2
                 MVec.unsafeWrite nMap (unK n1) (Just n2)
                 MVec.unsafeWrite nSet (unK n2) True
                 checkT (e1 M.! n1) (e2 M.! n2)
     checkT r1 r2