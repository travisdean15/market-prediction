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

;; Public functions

;; Create a new prediction market
(define-public (create-market
        (description (string-ascii 500))
        (outcomes (list 10 (string-ascii 100)))
        (end-time uint)
    )
    (let (
            (market-id (var-get next-market-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (> (len description) u0) ERR-INVALID-DESCRIPTION)
        (asserts! (<= (len description) MAX-DESCRIPTION-LENGTH)
            ERR-INVALID-DESCRIPTION
        )
        (asserts! (> (len outcomes) u1) ERR-INVALID-OUTCOME)
        (asserts! (<= (len outcomes) MAX-OUTCOMES) ERR-INVALID-OUTCOME)
        (asserts! (> end-time current-time) ERR-MARKET-EXPIRED)

        ;; Initialize outcome pools to all zeros
        (let ((zero-pools (list u0 u0 u0 u0 u0 u0 u0 u0 u0 u0)))
            (map-set markets { market-id: market-id } {
                creator: tx-sender,
                description: description,
                outcomes: outcomes,
                end-time: end-time,
                resolved: false,
                winning-outcome: none,
                total-pool: u0,
                outcome-pools: zero-pools,
            })
        )

        ;; Initialize empty bettors list
        (map-set market-bettors { market-id: market-id } { bettors: (list) })

        (var-set next-market-id (+ market-id u1))
        (ok market-id)
    )
)

;; Place a bet on a specific outcome
(define-public (place-bet
        (market-id uint)
        (outcome uint)
        (amount uint)
    )
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-MARKET-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-MARKET-NOT-FOUND)
        (asserts! (>= amount MIN-BET-AMOUNT) ERR-INSUFFICIENT-AMOUNT)

        (let (
                (market (unwrap! (map-get? markets { market-id: market-id })
                    ERR-MARKET-NOT-FOUND
                ))
                (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
                (existing-bet (map-get? bets {
                    market-id: market-id,
                    bettor: tx-sender,
                }))
                (outcome-total (default-to u0
                    (get total
                        (map-get? outcome-totals {
                            market-id: market-id,
                            outcome: outcome,
                        })
                    )))
                (current-bettors (default-to (list)
                    (get bettors
                        (map-get? market-bettors { market-id: market-id })
                    )))
            )
            ;; Validate market and bet conditions
            (asserts! (< current-time (get end-time market)) ERR-MARKET-CLOSED)
            (asserts! (not (get resolved market)) ERR-MARKET-RESOLVED)
            (asserts! (< outcome (len (get outcomes market))) ERR-INVALID-OUTCOME)
            (asserts! (is-none existing-bet) ERR-NOT-AUTHORIZED)
            ;; One bet per user per market

            ;; Transfer STX to contract for escrow
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

            ;; Record the bet
            (map-set bets {
                market-id: market-id,
                bettor: tx-sender,
            } {
                outcome: outcome,
                amount: amount,
                withdrawn: false,
            })

            ;; Update outcome total
            (map-set outcome-totals {
                market-id: market-id,
                outcome: outcome,
            } { total: (+ outcome-total amount) }
            )

            ;; Add bettor to the list if not already present
            (map-set market-bettors { market-id: market-id } { bettors: (unwrap-panic (as-max-len? (append current-bettors tx-sender) u1000)) })

            ;; Update market total pool
            (map-set markets { market-id: market-id }
                (merge market { total-pool: (+ (get total-pool market) amount) })
            )

            (ok true)
        )
    )
)

;; Resolve market (admin/oracle function)
(define-public (resolve-market
        (market-id uint)
        (winning-outcome uint)
    )
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-MARKET-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-MARKET-NOT-FOUND)

        (let (
                (market (unwrap! (map-get? markets { market-id: market-id })
                    ERR-MARKET-NOT-FOUND
                ))
                (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
            )
            ;; Only contract owner or market creator can resolve
            (asserts!
                (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get creator market)))
                ERR-NOT-AUTHORIZED
            )
            (asserts! (>= current-time (get end-time market)) ERR-MARKET-CLOSED)
            (asserts! (not (get resolved market)) ERR-MARKET-RESOLVED)
            (asserts! (< winning-outcome (len (get outcomes market)))
                ERR-INVALID-OUTCOME
            )

            ;; Update market with resolution
            (map-set markets { market-id: market-id }
                (merge market {
                    resolved: true,
                    winning-outcome: (some winning-outcome),
                })
            )

            (ok true)
        )
    )
)

;; Withdraw winnings for a resolved market
(define-public (withdraw-winnings (market-id uint))
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-MARKET-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-MARKET-NOT-FOUND)

        (let (
                (market (unwrap! (map-get? markets { market-id: market-id })
                    ERR-MARKET-NOT-FOUND
                ))
                (bet (unwrap!
                    (map-get? bets {
                        market-id: market-id,
                        bettor: tx-sender,
                    })
                    ERR-NO-WINNINGS
                ))
                (winning-outcome (unwrap! (get winning-outcome market) ERR-MARKET-NOT-RESOLVED))
                (total-pool (get total-pool market))
                (winning-pool (default-to u0
                    (get total
                        (map-get? outcome-totals {
                            market-id: market-id,
                            outcome: winning-outcome,
                        })
                    )))
            )
            ;; Validate withdrawal conditions
            (asserts! (get resolved market) ERR-MARKET-NOT-RESOLVED)
            (asserts! (not (get withdrawn bet)) ERR-ALREADY-WITHDRAWN)
            (asserts! (is-eq (get outcome bet) winning-outcome) ERR-NO-WINNINGS)
            (asserts! (> winning-pool u0) ERR-NO-WINNINGS)

            ;; Calculate proportional winnings
            (let (
                    (bet-amount (get amount bet))
                    (winnings (/ (* total-pool bet-amount) winning-pool))
                )
                ;; Mark as withdrawn
                (map-set bets {
                    market-id: market-id,
                    bettor: tx-sender,
                }
                    (merge bet { withdrawn: true })
                )

                ;; Transfer winnings
                (try! (as-contract (stx-transfer? winnings tx-sender tx-sender)))

                (ok winnings)
            )
        )
    )
)

;; Read-only functions

;; Get market information
(define-read-only (get-market (market-id uint))
    (map-get? markets { market-id: market-id })
)

;; Get bet information
(define-read-only (get-bet
        (market-id uint)
        (bettor principal)
    )
    (map-get? bets {
        market-id: market-id,
        bettor: bettor,
    })
)

;; Get outcome total for a specific outcome in a market
(define-read-only (get-outcome-total
        (market-id uint)
        (outcome uint)
    )
    (default-to u0
        (get total
            (map-get? outcome-totals {
                market-id: market-id,
                outcome: outcome,
            })
        ))
)

;; Get current market ID counter
(define-read-only (get-next-market-id)
    (var-get next-market-id)
)

;; Calculate potential winnings for a bettor
(define-read-only (calculate-potential-winnings
        (market-id uint)
        (bettor principal)
    )
    (match (map-get? markets { market-id: market-id })
        market
        (match (map-get? bets {
            market-id: market-id,
            bettor: bettor,
        })
            bet
            (if (get resolved market)
                (match (get winning-outcome market)
                    winning-outcome (if (is-eq (get outcome bet) winning-outcome)
                        (let (
                                (total-pool (get total-pool market))
                                (winning-pool (get-outcome-total market-id winning-outcome))
                                (bet-amount (get amount bet))
                            )
                            (if (> winning-pool u0)
                                (some (/ (* total-pool bet-amount) winning-pool))
                                (some u0)
                            )
                        )
                        (some u0)
                    )
                    (some u0)
                )
                none ;; Market not resolved yet
            )
            none ;; No bet found
        )
        none ;; Market not found
    )
)

;; Check if market is active (not expired and not resolved)
(define-read-only (is-market-active (market-id uint))
    (match (map-get? markets { market-id: market-id })
        market (let ((current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1)))))
            (and
                (< current-time (get end-time market))
                (not (get resolved market))
            )
        )
        false
    )
)

;; Get all bettors for a market
(define-read-only (get-market-bettors (market-id uint))
    (default-to (list)
        (get bettors (map-get? market-bettors { market-id: market-id }))
    )
)

;; Private functions

;; Helper function to validate outcome index
(define-private (is-valid-outcome
        (market-id uint)
        (outcome uint)
    )
    (match (map-get? markets { market-id: market-id })
        market (< outcome (len (get outcomes market)))
        false
    )
)
