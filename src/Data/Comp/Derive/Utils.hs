{-# LANGUAGE CPP #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  Data.Comp.Derive.Utils
-- Copyright   :  (c) 2010-2011 Patrick Bahr
-- License     :  BSD3
-- Maintainer  :  Patrick Bahr <paba@diku.dk>
-- Stability   :  experimental
-- Portability :  non-portable (GHC Extensions)
--
-- This module defines some utility functions for deriving instances
-- for functor based type classes.
--
--------------------------------------------------------------------------------
module Data.Comp.Derive.Utils where


import Control.Monad
import Language.Haskell.TH
import Language.Haskell.TH.Syntax
import Language.Haskell.TH.ExpandSyns

data DataInfo flag = DataInfo Cxt Name [TyVarBndr flag] [Con] [DerivClause] 


{-|
  This is the @Q@-lifted version of 'abstractNewtype.
-}
abstractNewtypeQ :: Q Info -> Q (Maybe (DataInfo ()))
abstractNewtypeQ = liftM abstractNewtype

{-|
  This function abstracts away @newtype@ declaration, it turns them into
  @data@ declarations.
-}
abstractNewtype :: Info -> Maybe (DataInfo ())
abstractNewtype (TyConI (NewtypeD cxt name args _ constr derive))
    = Just (DataInfo cxt name args [constr] derive)
abstractNewtype (TyConI (DataD cxt name args _ constrs derive))
    = Just (DataInfo cxt name args constrs derive)
abstractNewtype _ = Nothing

{-| This function provides the name and the arity of the given data
constructor, and if it is a GADT also its type.
-}
normalCon :: Con -> (Name,[StrictType], Maybe Type)
normalCon (NormalC constr args) = (constr, args, Nothing)
normalCon (RecC constr args) = (constr, map (\(_,s,t) -> (s,t)) args, Nothing)
normalCon (InfixC a constr b) = (constr, [a,b], Nothing)
normalCon (ForallC _ _ constr) = normalCon constr
normalCon (GadtC (constr:_) args typ) = (constr,args,Just typ)
normalCon _ = error "missing case for 'normalCon'"

normalCon' :: Con -> (Name,[Type], Maybe Type)
normalCon' con = (n, map snd ts, t)
  where (n, ts, t) = normalCon con
      

-- -- | Same as normalCon' but expands type synonyms.
-- normalConExp :: Con -> Q (Name,[Type])
-- normalConExp c = do
--   let (n,ts,t) = normalCon' c
--   ts' <- mapM expandSyns ts
--   return (n, ts')

-- | Same as normalCon' but expands type synonyms.
normalConExp :: Con -> Q (Name,[Type], Maybe Type)
normalConExp c = do
  let (n,ts,t) = normalCon' c
  return (n, ts,t)


-- | Same as normalConExp' but retains strictness annotations.
normalConStrExp :: Con -> Q (Name,[StrictType], Maybe Type)
normalConStrExp c = do
  let (n,ts,t) = normalCon c
  ts' <- mapM (\ (st,ty) -> do ty' <- expandSyns ty; return (st,ty')) ts
  return (n, ts',t)

-- | Auxiliary function to extract the first argument of a binary type
-- application (the second argument of this function). If the second
-- argument is @Nothing@ or not of the right shape, the first argument
-- is returned as a default.

getBinaryFArg :: Type -> Maybe Type -> Type
getBinaryFArg _ (Just (AppT (AppT _ t)  _)) = t
getBinaryFArg def _ = def

-- | Auxiliary function to extract the first argument of a type
-- application (the second argument of this function). If the second
-- argument is @Nothing@ or not of the right shape, the first argument
-- is returned as a default.
getUnaryFArg :: Type -> Maybe Type -> Type
getUnaryFArg _ (Just (AppT _ t)) = t
getUnaryFArg def _ = def



{-|
  This function provides the name and the arity of the given data constructor.
-}
abstractConType :: Con -> (Name,Int)
abstractConType (NormalC constr args) = (constr, length args)
abstractConType (RecC constr args) = (constr, length args)
abstractConType (InfixC _ constr _) = (constr, 2)
abstractConType (ForallC _ _ constr) = abstractConType constr
abstractConType (GadtC (constr:_) args _typ) = (constr,length args) -- Only first Name
abstractConType _ = error "missing case for 'abstractConType'"

{-|
  This function returns the name of a bound type variable
-}
tyVarBndrName (PlainTV n _) = n
tyVarBndrName (KindedTV n _ _) = n

containsType :: Type -> Type -> Bool
containsType s t
             | s == t = True
             | otherwise = case s of
                             ForallT _ _ s' -> containsType s' t
                             AppT s1 s2 -> containsType s1 t || containsType s2 t
                             SigT s' _ -> containsType s' t
                             _ -> False

containsType' :: Type -> Type -> [Int]
containsType' = run 0
    where run n s t
             | s == t = [n]
             | otherwise = case s of
                             ForallT _ _ s' -> run n s' t
                             -- only going through the right-hand side counts!
                             AppT s1 s2 -> run n s1 t ++ run (n+1) s2 t
                             SigT s' _ -> run n s' t
                             _ -> []


{-|
  This function provides a list (of the given length) of new names based
  on the given string.
-}
newNames :: Int -> String -> Q [Name]
newNames n name = replicateM n (newName name)

tupleTypes n m = map tupleTypeName [n..m]

{-| Helper function for generating a list of instances for a list of named
 signatures. For example, in order to derive instances 'Functor' and
 'ShowF' for a signature @Exp@, use derive as follows (requires Template
 Haskell):

 > $(derive [makeFunctor, makeShowF] [''Exp])
 -}
derive :: [Name -> Q [Dec]] -> [Name] -> Q [Dec]
derive ders names = liftM concat $ sequence [der name | der <- ders, name <- names]

{-| Apply a class name to type arguments to construct a type class
    constraint.
-}

mkClassP :: Name -> [Type] -> Type
mkClassP name = foldl AppT (ConT name)

{-| This function checks whether the given type constraint is an
equality constraint. If so, the types of the equality constraint are
returned. -}

isEqualP :: Type -> Maybe (Type, Type)
isEqualP (AppT (AppT EqualityT x) y) = Just (x, y)
isEqualP _ = Nothing

mkInstanceD :: Cxt -> Type -> [Dec] -> Dec
mkInstanceD cxt ty decs = InstanceD Nothing cxt ty decs



-- | This function lifts type class instances over sums
-- ofsignatures. To this end it assumes that it contains only methods
-- with types of the form @f t1 .. tn -> t@ where @f@ is the signature
-- that is used to construct sums. Since this function is generic it
-- assumes as its first argument the name of the function that is
-- used to lift methods over sums i.e. a function of type
--
-- @
-- (f t1 .. tn -> t) -> (g t1 .. tn -> t) -> ((f :+: g) t1 .. tn -> t)
-- @
--
-- where @:+:@ is the sum type constructor. The second argument to
-- this function is expected to be the name of that constructor. The
-- last argument is the name of the class whose instances should be
-- lifted over sums.

liftSumGen :: Name -> Name -> Name -> Q [Dec]
liftSumGen caseName sumName fname = do
  ClassI (ClassD _ name targs_ _ decs) _ <- reify fname
  let targs = map tyVarBndrName targs_
  splitM <- findSig targs decs
  case splitM of
    Nothing -> do reportError $ "Class " ++ show name ++ " cannot be lifted to sums!"
                  return []
    Just (ts1_, ts2_) -> do
      let f = VarT $ mkName "f"
      let g = VarT $ mkName "g"
      let ts1 = map VarT ts1_
      let ts2 = map VarT ts2_
      let cxt = [mkClassP name (ts1 ++ f : ts2),
                 mkClassP name (ts1 ++ g : ts2)]
      let tp = ((ConT sumName `AppT` f) `AppT` g)
      let complType = foldl AppT (foldl AppT (ConT name) ts1 `AppT` tp) ts2
      decs' <- sequence $ concatMap decl decs
      return [mkInstanceD cxt complType decs']
        where decl :: Dec -> [DecQ]
              decl (SigD f _) = [funD f [clause f]]
              decl _ = []
              clause :: Name -> ClauseQ
              clause f = do x <- newName "x"
                            let b = NormalB (VarE caseName `AppE` VarE f `AppE` VarE f `AppE` VarE x)
                            return $ Clause [VarP x] b []


findSig :: [Name] -> [Dec] -> Q (Maybe ([Name],[Name]))
findSig targs decs = case map run decs of
                       []  -> return Nothing
                       mx:_ -> do x <- mx
                                  case x of
                                    Nothing -> return Nothing
                                    Just n -> return $ splitNames n targs
  where run :: Dec -> Q (Maybe Name)
        run (SigD _ ty) = do
          ty' <- expandSyns ty
          return $ getSig False ty'
        run _ = return Nothing
        getSig t (ForallT _ _ ty) = getSig t ty
        getSig False (AppT (AppT ArrowT ty) _) = getSig True ty
        getSig True (AppT ty _) = getSig True ty
        getSig True (VarT n) = Just n
        getSig _ _ = Nothing
        splitNames y (x:xs)
          | y == x = Just ([],xs)
          | otherwise = do (xs1,xs2) <- splitNames y xs
                           return (x:xs1,xs2)
        splitNames _ [] = Nothing
