{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, FlexibleContexts #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  Data.ALaCarte.Decompose
-- Copyright   :  3gERP, 2010
-- License     :  AllRightsReserved
-- Maintainer  :  Tom Hvitved, Patrick Bahr, and Morten Ib Nielsen
-- Stability   :  unknown
-- Portability :  unknown
--
-- This module implements the decomposition of terms into function
-- symbols and arguments resp. variables.
--
--------------------------------------------------------------------------------
module Data.ALaCarte.Decompose (
  Decomp (..),
  DecompTerm,
  Decompose (..),
  structure,
  arguments,
  decompose
  ) where

import Data.ALaCarte.Term
import Data.ALaCarte.Variables
import Data.Foldable

{-| This function computes the structure of a functorial value. -}

structure :: (Functor f) => f a -> Const f
structure = fmap (const ())

{-| This function computes the arguments of a functorial value.  -}

arguments :: (Foldable f) => f a -> [a]
arguments = toList

{-| This type represents decompositions of functorial values. -}

data Decomp f v a = Var v
                  | Fun (Const f) [a]

{-| This type represents decompositions of terms.  -}

type DecompTerm f v = Decomp f v (Term f)

{-| This class specifies the decomposability of a functorial value. -}

class Decompose f v a where
    {-| This function decomposes a functorial value. -}

    decomp :: f a -> Decomp f v a

instance (HasVars f v, Functor f, Foldable f) => Decompose f v a where
    decomp t = case isVar t of
                 Just v -> Var v
                 Nothing -> Fun sym args
                     where sym = fmap (const ()) t
                           args = arguments t

{-| This function decomposes a term. -}

decompose :: (Decompose f v (Term f)) => Term f -> DecompTerm f v
decompose (Term t) = decomp t