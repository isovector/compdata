module Main where

import Test.Framework
import qualified Data.ALaCarte_Test

--------------------------------------------------------------------------------
-- Test Suits
--------------------------------------------------------------------------------

main = defaultMain [tests]

tests = testGroup "Data" [
         Data.ALaCarte_Test.tests
       ]

--------------------------------------------------------------------------------
-- Properties
--------------------------------------------------------------------------------