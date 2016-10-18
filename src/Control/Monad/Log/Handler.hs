{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-|
Collections of different handler for use with MonadLog
-}
module Control.Monad.Log.Handler where

import Control.Lens ((&), (.~))
import Control.Retry (recovering, exponentialBackoff, logRetries, defaultLogMsg)
import Data.Text (Text)
import Network.Google (runResourceT, runGoogle, send, Error(TransportError, ServiceError))
import Network.Google.Logging
       (MonitoredResource, WriteLogEntriesRequestLabels, LogEntry,
        entriesWrite, writeLogEntriesRequest, wlerLogName, wlerLabels,
        wlerResource, wlerEntries)
import Network.Google.PubSub
       (PubsubMessage, projectsTopicsPublish, publishRequest, prMessages)
import Network.Google.Auth.Scope (HasScope', AllowScopes)
import Network.Google.Env (HasEnv)
import Control.Monad.Log (BatchingOptions, Handler, withBatchedHandler)
import Control.Monad.IO.Class (MonadIO(liftIO))
import Control.Monad.Catch (MonadMask)


-- | `withGoogleLoggingHandler` creates a new `Handler` for flash logs to
-- <https://cloud.google.com/logging/ Google Logging>
withGoogleLoggingHandler
    :: (HasScope' s '["https://www.googleapis.com/auth/cloud-platform",
                      "https://www.googleapis.com/auth/logging.admin",
                      "https://www.googleapis.com/auth/logging.write"] ~ 'True
       ,AllowScopes s
       ,HasEnv s r
       ,MonadIO io
       ,MonadMask io)
    => BatchingOptions
    -> r
    -> Maybe Text
    -> Maybe MonitoredResource
    -> Maybe WriteLogEntriesRequestLabels
    -> (Handler io LogEntry -> io a)
    -> io a
withGoogleLoggingHandler options env logname resource labels =
    withBatchedHandler options (flushToGoogleLogging env logname resource labels)


-- | method for flash log to <https://cloud.google.com/logging/ Google Logging>
flushToGoogleLogging
    :: (HasScope' s '["https://www.googleapis.com/auth/cloud-platform",
                      "https://www.googleapis.com/auth/logging.admin",
                      "https://www.googleapis.com/auth/logging.write"] ~ 'True
       ,AllowScopes s
       ,HasEnv s r)
    => r
    -> Maybe Text
    -> Maybe MonitoredResource
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
                        send
                            (entriesWrite
                                 ((((writeLogEntriesRequest & wlerEntries .~ entries)
                                                            & wlerLabels .~ labels)
                                                            & wlerResource .~ resource)
                                                            & wlerLogName .~ logname))) >>
              return ()))



-- | `withGooglePubSubHandler` creates a new `Handler` for flash logs to
-- <https://cloud.google.com/pubsub/ Google PubSub>
withGooglePubSubHandler
    :: (HasScope' s '["https://www.googleapis.com/auth/cloud-platform",
                      "https://www.googleapis.com/auth/pubsub"] ~ 'True
       ,AllowScopes s
       ,HasEnv s r
       ,MonadIO io
       ,MonadMask io)
    => BatchingOptions
    -> r
    -> Text
    -> (Handler io PubsubMessage -> io a)
    -> io a
withGooglePubSubHandler options env topic =
    withBatchedHandler options (flushToGooglePubSub env topic)


-- | method for flash log to <https://cloud.google.com/pubsub/ Google PubSub>
flushToGooglePubSub
    :: (HasScope' s '["https://www.googleapis.com/auth/cloud-platform",
                      "https://www.googleapis.com/auth/pubsub"] ~ 'True
       ,AllowScopes s
       ,HasEnv s r)
    => r
    -> Text
    -> [PubsubMessage]
    -> IO ()
flushToGooglePubSub env topic msgs =
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
                        send (projectsTopicsPublish (publishRequest & prMessages .~ msgs) topic)) >>
              return ()))
