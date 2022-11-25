module Classless.EncodeJson.Generic
  ( class EncodeLiteral
  , class EncodeRep
  , class EncodeRepArgs
  , class Sum
  , encodeLiteral
  , encodeLiteralSum
  , encodeLiteralSumWithTransform
  , encodeRep
  , encodeRepArgs
  , encodeRepWith
  , sum
  , sumWith
  ) where

import Prelude

import Classless (type (~), NoArgs, (~))
import Data.Argonaut.Core (Json, fromArray, fromObject, fromString)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep as Rep
import Data.Symbol (class IsSymbol, reflectSymbol)
import Foreign.Object as FO
import Partial.Unsafe (unsafeCrashWith)
import Prim.Row (class Cons, class Lacks)
import Prim.TypeError (class Fail, Text)
import Record as Record
import Type.Equality (class TypeEquals)
import Type.Proxy (Proxy(..))

type Encoding =
  { tagKey :: String
  , valuesKey :: String
  , unwrapSingleArguments :: Boolean
  }

defaultEncoding :: Encoding
defaultEncoding =
  { tagKey: "tag"
  , valuesKey: "values"
  , unwrapSingleArguments: false
  }

class EncodeRep sumSpec r | r -> sumSpec where
  encodeRepWith :: { | sumSpec } -> Encoding -> r -> Json

encodeRep :: forall sumSpec r. EncodeRep sumSpec r => { | sumSpec } -> r -> Json
encodeRep sumSpec = encodeRepWith sumSpec defaultEncoding

instance encodeRepNoConstructors :: EncodeRep () Rep.NoConstructors where
  encodeRepWith e = encodeRepWith e

instance encodeRepSum ::
  ( TypeEquals a (Rep.Constructor name xx)
  , Cons name x sumSpec' sumSpec
  , Cons name x () sumSpec'' 
  , EncodeRep sumSpec'' a
  , EncodeRep sumSpec' b
  , IsSymbol name
  , Lacks name sumSpec'
  ) =>
  EncodeRep sumSpec (Rep.Sum a b) where
  encodeRepWith sp e (Rep.Inl a) = encodeRepWith (Record.insert (Proxy :: _ name) (Record.get (Proxy :: _ name) sp) {}) e a
  encodeRepWith sp e (Rep.Inr b) = encodeRepWith (Record.delete (Proxy :: _ name) sp) e b

-- instance encodeRepConstructorNoArguments ::
--   ( IsSymbol name
--   ) =>
--   EncodeRep sumSpec (Rep.Constructor name NoArguments) where
--   encodeRepWith _ e (Rep.Constructor a) =
--     fromObject
--       $ FO.insert e.tagKey (fromString (reflectSymbol (Proxy :: Proxy name)))
--       $ FO.insert e.valuesKey values
--       $ FO.empty
--     where
--     values = fromArray []

instance encodeRepConstructor ::
  ( IsSymbol name
  , EncodeRepArgs prodSpec a
  , Cons name prodSpec () sumSpec
  ) =>
  EncodeRep sumSpec (Rep.Constructor name a) where
  encodeRepWith sumSpec e (Rep.Constructor a) =
    fromObject
      $ FO.insert e.tagKey (fromString (reflectSymbol (Proxy :: Proxy name)))
      $ FO.insert e.valuesKey values
      $ FO.empty
    where
    values =
      let
        prodSpec = Record.get (Proxy :: _ name) sumSpec
        vs = encodeRepArgs prodSpec a
      in
        if e.unwrapSingleArguments then case vs of
          [ v ] -> v
          _ -> fromArray vs
        else fromArray vs

class EncodeRepArgs prodSpec r | r -> prodSpec where
  encodeRepArgs :: prodSpec -> r -> Array Json

instance encodeRepArgsNoArguments :: EncodeRepArgs NoArgs Rep.NoArguments where
  encodeRepArgs _ Rep.NoArguments = []

instance encodeRepArgsProduct :: (EncodeRepArgs sa a, EncodeRepArgs sb b) => EncodeRepArgs (sa ~ sb) (Rep.Product a b) where
  encodeRepArgs (spA ~ spB) (Rep.Product a b) = encodeRepArgs spA a <> encodeRepArgs spB b

instance encodeRepArgsArgument :: EncodeRepArgs (a -> Json) (Rep.Argument a) where
  encodeRepArgs spec (Rep.Argument a) = [ spec a ]


class Sum sumSpec a | a -> sumSpec where
  sum :: { | sumSpec } -> (a -> Json)

instance (Generic a rep, EncodeRep sumSpec rep) => Sum sumSpec a where
  sum spec = sumWith spec defaultEncoding

-- | Encode any `Generic` data structure into `Json`.
-- | Takes a record for encoding settings.
sumWith :: forall sumSpec a r. Rep.Generic a r => EncodeRep sumSpec r => { | sumSpec } -> Encoding -> a -> Json
sumWith spec e = encodeRepWith spec e <<< Rep.from

-- | A function for encoding `Generic` sum types using string literal representations.
encodeLiteralSum :: forall a r. Rep.Generic a r => EncodeLiteral r => a -> Json
encodeLiteralSum = encodeLiteralSumWithTransform identity

-- | A function for encoding `Generic` sum types using string literal representations.
-- | Takes a function for transforming the tag name in encoding.
encodeLiteralSumWithTransform :: forall a r. Rep.Generic a r => EncodeLiteral r => (String -> String) -> a -> Json
encodeLiteralSumWithTransform tagNameTransform = encodeLiteral tagNameTransform <<< Rep.from

class EncodeLiteral r where
  encodeLiteral :: (String -> String) -> r -> Json

instance encodeLiteralSumInst :: (EncodeLiteral a, EncodeLiteral b) => EncodeLiteral (Rep.Sum a b) where
  encodeLiteral tagNameTransform (Rep.Inl a) = encodeLiteral tagNameTransform a
  encodeLiteral tagNameTransform (Rep.Inr b) = encodeLiteral tagNameTransform b

instance encodeLiteralConstructor :: (IsSymbol name) => EncodeLiteral (Rep.Constructor name Rep.NoArguments) where
  encodeLiteral tagNameTransform _ = fromString <<< tagNameTransform $ reflectSymbol (Proxy :: Proxy name)

type FailMessage =
  Text """`encodeLiteralSum` can only be used with sum types, where all of the constructors are nullary. This is because a string literal cannot be encoded into a product type."""

instance encodeLiteralConstructorCannotBeProduct ::
  Fail FailMessage =>
  EncodeLiteral (Rep.Product a b) where
  encodeLiteral _ _ = unsafeCrashWith "unreachable encodeLiteral was reached."
