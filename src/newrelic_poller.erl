-module(newrelic_poller).
-behaviour(gen_server).

%% API
-export([start_link/1, start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {poll_fun, error_cb}).

%%
%% API
%%

start_link(PollF) ->
    start_link(PollF, fun default_error_cb/2).

start_link(PollF, ErrorCb) ->
    gen_server:start_link(?MODULE, [PollF, ErrorCb], []).

%%
%% gen_server callbacks
%%

init([PollF, ErrorCb]) ->
    erlang:send_after(60000, self(), poll),
    {ok, #state{poll_fun = PollF, error_cb = ErrorCb}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(poll, State) ->
    erlang:send_after(60000, self(), poll),

    {ok, Hostname} = inet:gethostname(),

    case catch (State#state.poll_fun)() of
        {[], []} ->
            ok;
        {'EXIT', Error} ->
            (State#state.error_cb)(poll_failed, Error),
            ok;
        {Metrics, Errors} ->
            {ok, Type} = application:get_env(newrelic, api_type),
            push(Type, Hostname, Metrics, Errors, State)
    end,

    {noreply, State};

handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
%% Internal functions
%%

default_error_cb(poll_failed, Error) ->
    error_logger:warning_msg("newrelic_poller: polling failed: ~p~n", [Error]);
default_error_cb(push_failed, Error) ->
    error_logger:warning_msg("newrelic_poller: push failed: ~p~n", [Error]).

push(collector, Hostname, Metrics, Errors, State) ->
    case catch newrelic:push(Hostname, Metrics, Errors) of
        ok ->
            ok;
        Error ->
            (State#state.error_cb)(push_failed, Error),
            ok
    end;
push(_, Hostname, Metrics, Errors, _State) ->
    case catch newrelic_plugin:push(Hostname, Metrics, Errors) of
        ok ->
            ok;
        Error ->
            % Don't really know what to do here yet.
            ok
    end.
