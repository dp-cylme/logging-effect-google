{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-|
Collections of different handler for use with MonadLog
-}
module Control.Monad.Log.Handler where

import Control.Retry (recovering, exponentialBackoff, logRetries, defaultLogMsg)
import Data.Text (Text)
import Network.Google (HasEnv, runResourceT, runGoogle, send, Error(TransportError, ServiceError))
import Network.Google.Logging
       (MonitoredResource, WriteLogEntriesRequestLabels, LogEntry, entriesWrite, writeLogEntriesRequest)
import Control.Monad.Log (BatchingOptions, Handler, withBatchedHandler)
import Control.Monad.IO.Class (MonadIO(liftIO))
import Control.Monad.Catch (MonadMask)

-- | `withGoogleLoggingHandler` creates a new `Handler` for flash logs to <https://cloud.google.com/logging/ Google Logging>
withGoogleLoggingHandler
    :: (HasEnv '["https://www.googleapis.com/auth/cloud-platform",
                 "https://www.googleapis.com/auth/logging.admin",
                 "https://www.googleapis.com/auth/logging.write"] r, MonadIO io, MonadMask io)
    => BatchingOptions
    -> r
    -> Text
    -> MonitoredResource
    -> Maybe WriteLogEntriesRequestLabels
    -> (Handler io LogEntry -> io a)
    -> io a
withGoogleLoggingHandler options env logname resource labels =
    withBatchedHandler options (flushToGoogleLogging env logname resource labels)


-- | method for flash log to <https://cloud.google.com/logging/ Google Logging>
flushToGoogleLogging
    :: (HasEnv '["https://www.googleapis.com/auth/cloud-platform",
                 "https://www.googleapis.com/auth/logging.admin",
                 "https://www.googleapis.com/auth/logging.write"] r)
    => r
    -> Text
    -> MonitoredResource
    -> Maybe WriteLogEntriesRequestLabels
    -> [LogEntry]
    -> IO ()
flushToGoogleLogging env logname resource labels entries =
    runResourceT
        (runGoogle
             env
             (recovering
                  (exponentialBackoff 15)
                  [ logRetries
                        (\(TransportError _) ->
                              return False)
                        (\b e rs ->
                              liftIO (print (defaultLogMsg b e rs)))
                  , logRetries
                        (\(ServiceError _) ->
                              return False)
                        (\b e rs ->
                              liftIO (print (defaultLogMsg b e rs)))]
                  (\_ ->
                        send (entriesWrite (writeLogEntriesRequest))) >>
              return ()))
