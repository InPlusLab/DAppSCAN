//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

library Errors {
  string constant ZERO_ADDRESS = "Zero address";
  string constant TEAM_NOT_INIT = "Team isn't initialized";

  string constant REG_STARTED = "Registration is already active";
  string constant REG_NOT_STARTED = "Registration isn't active";
  string constant ALREADY_REGISTERED = "Caller is already registered";
  
  string constant INVALID_DEADLINE = "Invalid deadline";
  string constant INVALID_PASS = "Invalid pass";
  string constant NOT_RIGHT_PASS = "Caller doesn't have the right pass";

  string constant LATE_FOR_QUEUE = "Caller is late for entering queue";
  string constant NO_TOURNAMENTS = "There are no tournaments to assign";
  string constant TOURNAMENT_LIMIT = "Tournament player limit reached";
  string constant TOURNAMENT_NOT_FINISHED = "Tournament isn't finished";
  string constant TOURNAMENT_EMPTY = "Tournament is empty";

  string constant NOT_COACH = "Caller is not coach of player";
  string constant NOT_CORE = "Caller is not a core account";
  string constant NOT_AUTHORIZED = "Caller is not an authorized contract";
  string constant NOT_ENOUGH_PLAYERS_STAKED = "Not enough players staked";
  string constant NOT_IN_TOURNAMENT = "Caller isn't in the tournament";

  string constant NEXT_MATCH_NOT_READY = "Next match is not ready";

  string constant TOKEN_CHECKOUT_FAIL = "Token checkout failed";
  string constant TOKEN_APPROVE_FAIL = "Token approve failed";

  string constant DUP_PLAYER = "Duplicate players";
  string constant INVALID_PLAYER = "Invalid player";

  string constant CALLABLE_IN_TOURNAMENT = "Only callable in tournaments";

  string constant PLAYER_LOCKED = "Player is already locked";
  string constant PLAYER_NOT_LOCKED = "Player is not locked";
  string constant PLAYER_NOT_VETERAN = "Player is not veteran";
  string constant PLAYER_NOT_RETIRED = "Player is not retired";

  string constant REQ_LATE = "Late request for random";
  string constant REQ_ALR_FULFILLED = "Request is already fulfilled";
  string constant REQ_NOT_FULFILLED = "Request isn't fulfilled";
  string constant RAND_NOT_READY = "Random number isn't ready";
  string constant RAND_EMPTY = "Random number is empty, request again";
  string constant ENOUGH_LINK = "Not enough LINK in contract";

  string constant SALE_NOT_ACTIVE = "Sale not active";
}