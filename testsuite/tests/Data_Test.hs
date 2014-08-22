module Main where

import Test.Framework
import qualified Data.Comp_Test

--------------------------------------------------------------------------------
-- Test Suits
--------------------------------------------------------------------------------

main = defaultMain [tests]

tests = testGroup "Data" [
         Data.Comp_Test.tests
       ]

--------------------------------------------------------------------------------
-- Properties
--------------------------------------------------------------------------------