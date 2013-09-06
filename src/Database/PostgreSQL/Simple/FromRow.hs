{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RoleAnnotations #-}

------------------------------------------------------------------------------
-- |
-- Module:      Database.PostgreSQL.Simple.FromRow
-- Copyright:   (c) 2012 Leon P Smith
-- License:     BSD3
-- Maintainer:  Leon P Smith <leon@melding-monads.com>
-- Stability:   experimental
--
-- The 'FromRow' typeclass, for converting a row of results
-- returned by a SQL query into a more useful Haskell representation.
--
-- Predefined instances are provided for tuples containing up to ten
-- elements.
------------------------------------------------------------------------------

module Database.PostgreSQL.Simple.FromRow
     ( FromRow(..)
     , RowParser
     , field
     , fieldWith
     , numFieldsRemaining
     ) where

import           Control.Applicative (Applicative(..), (<$>))
import           Control.Monad (replicateM)
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B
import           Data.Vector (Vector)
import qualified Data.Vector as V
import Database.PostgreSQL.Simple.Types (Only(..))
import qualified Database.PostgreSQL.LibPQ as PQ
import           Database.PostgreSQL.Simple.Internal
import           Database.PostgreSQL.Simple.Compat
import           Database.PostgreSQL.Simple.FromField
import           Database.PostgreSQL.Simple.Ok
import           Database.PostgreSQL.Simple.Types ((:.)(..))
import           Database.PostgreSQL.Simple.TypeInfo

import Control.Monad.Trans.State.Strict
import Control.Monad.Trans.Reader
import Control.Monad.Trans.Class

-- | A collection type that can be converted from a sequence of fields.
-- Instances are provided for tuples up to 10 elements and lists of any length.
--
-- Note that instances can be defined outside of postgresql-simple,  which is
-- often useful.   For example, here's an instance for a user-defined pair:
--
-- @data User = User { name :: String, fileQuota :: Int }
--
-- instance 'FromRow' User where
--     fromRow = User \<$\> 'field' \<*\> 'field'
-- @
--
-- The number of calls to 'field' must match the number of fields returned
-- in a single row of the query result.  Otherwise,  a 'ConversionFailed'
-- exception will be thrown.
--
-- Note that 'field' evaluates it's result to WHNF, so the caveats listed in
-- mysql-simple and very early versions of postgresql-simple no longer apply.
-- Instead, look at the caveats associated with user-defined implementations
-- of 'fromField'.

class FromRow a@N where
    fromRow :: RowParser a

getvalue :: PQ.Result -> PQ.Row -> PQ.Column -> Maybe ByteString
getvalue result row col = unsafeDupablePerformIO (PQ.getvalue result row col)

nfields :: PQ.Result -> PQ.Column
nfields result = unsafeDupablePerformIO (PQ.nfields result)

getTypeInfoByCol :: Row -> PQ.Column -> Conversion TypeInfo
getTypeInfoByCol Row{..} col =
    Conversion $ \conn -> do
      oid <- PQ.ftype rowresult col
      Ok <$> getTypeInfo conn oid

getTypenameByCol :: Row -> PQ.Column -> Conversion ByteString
getTypenameByCol row col = typname <$> getTypeInfoByCol row col

fieldWith :: FieldParser a -> RowParser a
fieldWith fieldP = RP $ do
    let unCol (PQ.Col x) = fromIntegral x :: Int
    r@Row{..} <- ask
    column <- lift get
    lift (put (column + 1))
    let ncols = nfields rowresult
    if (column >= ncols)
    then lift $ lift $ do
        vals <- mapM (getTypenameByCol r) [0..ncols-1]
        let err = ConversionFailed
                (show (unCol ncols) ++ " values: " ++ show (map ellipsis vals))
                Nothing
                ""
                ("at least " ++ show (unCol column + 1)
                  ++ " slots in target type")
                "mismatch between number of columns to \
                \convert and number in target type"
        conversionError err
    else do
      let !result = rowresult
          !typeOid = unsafeDupablePerformIO (PQ.ftype result column)
          !field = Field{..}
      lift (lift (fieldP field (getvalue result row column)))

field :: FromField a => RowParser a
field = fieldWith fromField

ellipsis :: ByteString -> ByteString
ellipsis bs
    | B.length bs > 15 = B.take 10 bs `B.append` "[...]"
    | otherwise        = bs

numFieldsRemaining :: RowParser Int
numFieldsRemaining = RP $ do
    Row{..} <- ask
    column <- lift get
    return $! (\(PQ.Col x) -> fromIntegral x) (nfields rowresult - column)

instance (FromField a) => FromRow (Only a) where
    fromRow = Only <$> field

instance (FromField a, FromField b) => FromRow (a,b) where
    fromRow = (,) <$> field <*> field

instance (FromField a, FromField b, FromField c) => FromRow (a,b,c) where
    fromRow = (,,) <$> field <*> field <*> field

instance (FromField a, FromField b, FromField c, FromField d) =>
    FromRow (a,b,c,d) where
    fromRow = (,,,) <$> field <*> field <*> field <*> field

instance (FromField a, FromField b, FromField c, FromField d, FromField e) =>
    FromRow (a,b,c,d,e) where
    fromRow = (,,,,) <$> field <*> field <*> field <*> field <*> field

instance (FromField a, FromField b, FromField c, FromField d, FromField e,
          FromField f) =>
    FromRow (a,b,c,d,e,f) where
    fromRow = (,,,,,) <$> field <*> field <*> field <*> field <*> field
                      <*> field

instance (FromField a, FromField b, FromField c, FromField d, FromField e,
          FromField f, FromField g) =>
    FromRow (a,b,c,d,e,f,g) where
    fromRow = (,,,,,,) <$> field <*> field <*> field <*> field <*> field
                       <*> field <*> field

instance (FromField a, FromField b, FromField c, FromField d, FromField e,
          FromField f, FromField g, FromField h) =>
    FromRow (a,b,c,d,e,f,g,h) where
    fromRow = (,,,,,,,) <$> field <*> field <*> field <*> field <*> field
                        <*> field <*> field <*> field

instance (FromField a, FromField b, FromField c, FromField d, FromField e,
          FromField f, FromField g, FromField h, FromField i) =>
    FromRow (a,b,c,d,e,f,g,h,i) where
    fromRow = (,,,,,,,,) <$> field <*> field <*> field <*> field <*> field
                         <*> field <*> field <*> field <*> field

instance (FromField a, FromField b, FromField c, FromField d, FromField e,
          FromField f, FromField g, FromField h, FromField i, FromField j) =>
    FromRow (a,b,c,d,e,f,g,h,i,j) where
    fromRow = (,,,,,,,,,) <$> field <*> field <*> field <*> field <*> field
                          <*> field <*> field <*> field <*> field <*> field

instance FromField a => FromRow [a] where
    fromRow = do
      n <- numFieldsRemaining
      replicateM n field

instance FromField a => FromRow (Vector a) where
    fromRow = do
      n <- numFieldsRemaining
      V.replicateM n field

instance (FromRow a, FromRow b) => FromRow (a :. b) where
    fromRow = (:.) <$> fromRow <*> fromRow
