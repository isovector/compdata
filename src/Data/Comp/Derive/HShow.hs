{-# LANGUAGE TemplateHaskell, TypeOperators #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  Data.Comp.Derive.HShow
-- Copyright   :  3gERP, 2011
-- License     :  AllRightsReserved
-- Maintainer  :  Patrick Bahr, Tom Hvitved
-- Stability   :  unknown
-- Portability :  unknown
--
--
--------------------------------------------------------------------------------

module Data.Comp.Derive.HShow
    ( HShowF(..),
      KShow(..),
      instanceHShowF
    ) where

import Data.Comp.Derive.Utils
import Data.Comp.Multi.HFunctor
import Data.Comp.Multi.Algebra
import Language.Haskell.TH
import Data.List

class HShowF f where
    hshowF :: Alg f (K String)
    hshowF = K . hshowF'
    hshowF' :: f (K String) :=> String
    hshowF' = unK . hshowF
             
class KShow a where
    kshow :: a i -> K String i

showConstr :: String -> [String] -> String
showConstr con [] = con
showConstr con args = "(" ++ con ++ " " ++ concat (intersperse " " args) ++ ")"


instanceHShowF :: Name -> Q [Dec]
instanceHShowF fname = do
  TyConI (DataD _cxt name args constrs _deriving) <- abstractNewtypeQ $ reify fname
  let args' = init args
      fArg = VarT . tyVarBndrName $ last args'
      argNames = (map (VarT . tyVarBndrName) (init args'))
      complType = foldl AppT (ConT name) argNames
      preCond = map (ClassP ''Show . (: [])) argNames
      classType = AppT (ConT ''HShowF) complType
  constrs' <- mapM normalConExp constrs
  showFDecl <- funD 'hshowF (showFClauses fArg constrs')
  return $ [InstanceD preCond classType [showFDecl]]
      where showFClauses fArg constrs = map (genShowFClause fArg) constrs
            filterFarg fArg ty x = (fArg == ty, varE x)
            mkShow (isFArg, var)
                | isFArg = var
                | otherwise = [| show $var |]
            genShowFClause fArg (constr, args) = do 
              let n = length args
              varNs <- newNames n "x"
              let pat = ConP constr $ map VarP varNs
                  allVars = zipWith (filterFarg fArg) args varNs
                  shows = listE $ map mkShow allVars
                  conName = nameBase constr
              body <- [|showConstr conName $shows|]
              return $ Clause [pat] (NormalB body) []
