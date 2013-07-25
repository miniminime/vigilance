{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE TemplateHaskell    #-}
{-# LANGUAGE TypeFamilies       #-}
module Utils.Vigilance.TableOps ( createWatch
                                , createWatchEvent
                                , CreateWatchEvent(..)
                                , createWatchS
                                , deleteWatch
                                , deleteWatchEvent
                                , DeleteWatchEvent(..)
                                , deleteWatchS
                                , findWatch
                                , findWatchEvent
                                , FindWatchEvent(..)
                                , findWatchS
                                , watchLens
                                , emptyTable) where

import Control.Lens
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ask)
import Control.Monad.State ( get
                           , put)
import Data.Acid
import Data.Acid.Advanced (update', query')
import Data.Table ( insert'
                  , with
                  , empty
                  , deleteWith)
import Data.Time.Clock.POSIX (POSIXTime)
import Utils.Vigilance.Types

createWatch :: NewWatch -> WatchTable -> (EWatch, WatchTable)
createWatch w = insert' $ w & watchId .~ (ID 0)

deleteWatch :: ID -> WatchTable -> WatchTable
deleteWatch i table = table & deleteWith WatchID (==) i

findWatch :: ID -> WatchTable -> Maybe EWatch
findWatch i table = table ^. at i

watchLens :: (Indexable ID p0, Profunctor p0)
             => p0 EWatch EWatch
             -> ID
             -> WatchTable
             -> WatchTable
watchLens f i table = table & ix i %~ f

checkInWatch :: POSIXTime -> ID -> WatchTable -> WatchTable
checkInWatch time = watchLens doCheckIn
  where doCheckIn          = transitionState . setTime
        setTime w          = w & watchWReport . wrLastCheckin .~ (Just time)
        transitionState w  = w & watchWReport . wrState %~ updateState
        updateState Paused = Paused
        updateState _      = Active

pauseWatch :: ID -> WatchTable -> WatchTable
pauseWatch = watchLens pause
  where pause w = w & watchWReport . wrState .~ Paused

emptyTable :: WatchTable
emptyTable = empty

-- ACID State
-- this compiles and is mega slick but needs testing
createWatchEvent :: NewWatch -> Update AppState EWatch
createWatchEvent w = wTable %%= (createWatch w)

deleteWatchEvent :: ID -> Update AppState ()
deleteWatchEvent i = wTable %= (deleteWatch i)

findWatchEvent :: ID -> Query AppState (Maybe EWatch)
findWatchEvent i = view (wTable . findWatch')
  where findWatch' = to $ findWatch i

$(makeAcidic ''AppState ['createWatchEvent, 'deleteWatchEvent, 'findWatchEvent])

createWatchS :: (UpdateEvent CreateWatchEvent, MonadIO m)
                => AcidState (EventState CreateWatchEvent)
                -> NewWatch
                -> m EWatch
createWatchS acid = update' acid . CreateWatchEvent

deleteWatchS :: (UpdateEvent DeleteWatchEvent, MonadIO m)
                => AcidState (EventState DeleteWatchEvent)
                -> ID
                -> m ()
deleteWatchS acid = update' acid . DeleteWatchEvent

findWatchS :: (QueryEvent FindWatchEvent, MonadIO m)
              => AcidState (EventState FindWatchEvent)
              -> ID
              -> m (Maybe EWatch)
findWatchS acid = query' acid . FindWatchEvent
