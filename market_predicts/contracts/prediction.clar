;; title: Prediction Market Smart Contract
;; version: 1.0.0
;; summary: A decentralized prediction market for betting on future events
;; description: Users can create markets, place bets with STX, and automatically distribute winnings

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-MARKET-NOT-FOUND (err u101))
(define-constant ERR-MARKET-CLOSED (err u102))
(define-constant ERR-MARKET-RESOLVED (err u103))
(define-constant ERR-MARKET-NOT-RESOLVED (err u104))
(define-constant ERR-INVALID-OUTCOME (err u105))
(define-constant ERR-INSUFFICIENT-AMOUNT (err u106))
(define-constant ERR-ALREADY-WITHDRAWN (err u107))
(define-constant ERR-NO-WINNINGS (err u108))
(define-constant ERR-TRANSFER-FAILED (err u109))
(define-constant ERR-MARKET-EXPIRED (err u110))
(define-constant ERR-INVALID-DESCRIPTION (err u111))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-BET-AMOUNT u1000000) ;; 1 STX in microSTX
(define-constant MAX-OUTCOMES u10)
(define-constant MAX-DESCRIPTION-LENGTH u500)

;; Data variables
(define-data-var next-market-id uint u1)

;; Market structure
(define-map markets
    { market-id: uint }
    {
        creator: principal,
        description: (string-ascii 500),
        outcomes: (list 10 (string-ascii 100)),
        end-time: uint,
        resolved: bool,
        winning-outcome: (optional uint),
        total-pool: uint,
        outcome-pools: (list 10 uint),
    }
)

;; Bet structure
(define-map bets
    {
        market-id: uint,
        bettor: principal,
    }
    {
        outcome: uint,
        amount: uint,
        withdrawn: bool,
    }
)

;; Track total bets per outcome per market
(define-map outcome-totals
    {
        market-id: uint,
        outcome: uint,
    }
    { total: uint }
)

;; Track all bettors for a market
(define-map market-bettors
    { market-id: uint }
    { bettors: (list 1000 principal) }
)
