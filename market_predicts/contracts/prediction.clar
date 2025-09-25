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
(define-constant ERR-DISPUTE-PERIOD-EXPIRED (err u112))
(define-constant ERR-DISPUTE-ALREADY-EXISTS (err u113))
(define-constant ERR-DISPUTE-NOT-FOUND (err u114))
(define-constant ERR-DISPUTE-PERIOD-ACTIVE (err u115))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-BET-AMOUNT u1000000) ;; 1 STX in microSTX
(define-constant MAX-OUTCOMES u10)
(define-constant MAX-DESCRIPTION-LENGTH u500)
(define-constant DEFAULT-PLATFORM-FEE u50) ;; 0.5% in basis points (50/10000)
(define-constant MAX-PLATFORM-FEE u1000) ;; 10% maximum fee
(define-constant BASIS-POINTS u10000) ;; 100% in basis points
(define-constant DISPUTE-PERIOD u144) ;; 24 hours in blocks (approx 10min per block)
(define-constant MIN-DISPUTE-STAKE u5000000) ;; 5 STX minimum dispute stake

;; Market categories
(define-constant CATEGORY-SPORTS u1)
(define-constant CATEGORY-POLITICS u2)
(define-constant CATEGORY-CRYPTO u3)
(define-constant CATEGORY-ENTERTAINMENT u4)
(define-constant CATEGORY-TECHNOLOGY u5)
(define-constant CATEGORY-FINANCE u6)
(define-constant CATEGORY-OTHER u7)
(define-constant MAX-CATEGORY u7)

;; Data variables
(define-data-var next-market-id uint u1)
(define-data-var platform-fee-rate uint DEFAULT-PLATFORM-FEE)
(define-data-var accumulated-fees uint u0)

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
        platform-fees: uint,
        dispute-end-time: (optional uint),
        disputed: bool,
        category: uint,
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

;; Category statistics
(define-map category-stats
    { category: uint }
    {
        total-markets: uint,
        active-markets: uint,
        total-volume: uint,
    }
)

;; User statistics tracking
(define-map user-stats
    { user: principal }
    {
        total-bets: uint,
        total-wagered: uint,
        total-winnings: uint,
        markets-created: uint,
        successful-predictions: uint,
        reputation-score: uint,
    }
)

;; Dispute tracking
(define-map disputes
    { market-id: uint }
    {
        challenger: principal,
        proposed-outcome: uint,
        stake: uint,
        created-at: uint,
        votes-for: uint,
        votes-against: uint,
        resolved: bool,
    }
)

;; Track dispute votes
(define-map dispute-votes
    {
        market-id: uint,
        voter: principal,
    }
    {
        vote: bool, ;; true = support dispute, false = oppose dispute
        stake: uint,
    }
)

;; Public functions

;; Create a new prediction market
(define-public (create-market
        (description (string-ascii 500))
        (outcomes (list 10 (string-ascii 100)))
        (end-time uint)
        (category uint)
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
        (asserts! (> category u0) ERR-INVALID-OUTCOME)
        (asserts! (<= category MAX-CATEGORY) ERR-INVALID-OUTCOME)

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
                platform-fees: u0,
                dispute-end-time: none,
                disputed: false,
                category: category,
            })
        )

        ;; Initialize empty bettors list
        (map-set market-bettors { market-id: market-id } { bettors: (list) })

        ;; Update category statistics
        (let (
                (current-stats (default-to 
                    { total-markets: u0, active-markets: u0, total-volume: u0 }
                    (map-get? category-stats { category: category })
                ))
            )
            (map-set category-stats { category: category } {
                total-markets: (+ (get total-markets current-stats) u1),
                active-markets: (+ (get active-markets current-stats) u1),
                total-volume: (get total-volume current-stats),
            })
        )

        ;; Update user statistics for market creation
        (let (
                (current-user-stats (default-to 
                    { total-bets: u0, total-wagered: u0, total-winnings: u0, markets-created: u0, successful-predictions: u0, reputation-score: u0 }
                    (map-get? user-stats { user: tx-sender })
                ))
            )
            (map-set user-stats { user: tx-sender } {
                total-bets: (get total-bets current-user-stats),
                total-wagered: (get total-wagered current-user-stats),
                total-winnings: (get total-winnings current-user-stats),
                markets-created: (+ (get markets-created current-user-stats) u1),
                successful-predictions: (get successful-predictions current-user-stats),
                reputation-score: (+ (get reputation-score current-user-stats) u10), ;; Bonus for creating markets
            })
        )

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

            ;; Calculate platform fee for this bet and update market
            (let (
                    (current-fee-rate (var-get platform-fee-rate))
                    (bet-fee (/ (* amount current-fee-rate) BASIS-POINTS))
                    (current-platform-fees (get platform-fees market))
                    (market-category (get category market))
                )
                ;; Update market total pool and platform fees
                (map-set markets { market-id: market-id }
                    (merge market { 
                        total-pool: (+ (get total-pool market) amount),
                        platform-fees: (+ current-platform-fees bet-fee)
                    })
                )
                
                ;; Update category volume statistics
                (let (
                        (current-stats (default-to 
                            { total-markets: u0, active-markets: u0, total-volume: u0 }
                            (map-get? category-stats { category: market-category })
                        ))
                    )
                    (map-set category-stats { category: market-category } {
                        total-markets: (get total-markets current-stats),
                        active-markets: (get active-markets current-stats),
                        total-volume: (+ (get total-volume current-stats) amount),
                    })
                )

                ;; Update user betting statistics
                (let (
                        (current-user-stats (default-to 
                            { total-bets: u0, total-wagered: u0, total-winnings: u0, markets-created: u0, successful-predictions: u0, reputation-score: u0 }
                            (map-get? user-stats { user: tx-sender })
                        ))
                    )
                    (map-set user-stats { user: tx-sender } {
                        total-bets: (+ (get total-bets current-user-stats) u1),
                        total-wagered: (+ (get total-wagered current-user-stats) amount),
                        total-winnings: (get total-winnings current-user-stats),
                        markets-created: (get markets-created current-user-stats),
                        successful-predictions: (get successful-predictions current-user-stats),
                        reputation-score: (+ (get reputation-score current-user-stats) u1), ;; Small rep boost for betting
                    })
                )
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

            ;; Update market with resolution and set dispute period
            (let (
                    (dispute-end (+ stacks-block-height DISPUTE-PERIOD))
                    (market-category (get category market))
                )
                (map-set markets { market-id: market-id }
                    (merge market {
                        resolved: true,
                        winning-outcome: (some winning-outcome),
                        dispute-end-time: (some dispute-end),
                    })
                )
                
                ;; Update category active markets count
                (let (
                        (current-stats (default-to 
                            { total-markets: u0, active-markets: u0, total-volume: u0 }
                            (map-get? category-stats { category: market-category })
                        ))
                    )
                    (map-set category-stats { category: market-category } {
                        total-markets: (get total-markets current-stats),
                        active-markets: (- (get active-markets current-stats) u1),
                        total-volume: (get total-volume current-stats),
                    })
                )
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
            ;; Check if dispute period has ended
            (match (get dispute-end-time market)
                dispute-end (asserts! (>= stacks-block-height dispute-end) ERR-DISPUTE-PERIOD-ACTIVE)
                true ;; No dispute period set
            )

            ;; Calculate proportional winnings with platform fee deduction
            (let (
                    (bet-amount (get amount bet))
                    (platform-fees (get platform-fees market))
                    (distributable-pool (- total-pool platform-fees))
                    (winnings (/ (* distributable-pool bet-amount) winning-pool))
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

                ;; Update user statistics for successful prediction
                (let (
                        (current-user-stats (default-to 
                            { total-bets: u0, total-wagered: u0, total-winnings: u0, markets-created: u0, successful-predictions: u0, reputation-score: u0 }
                            (map-get? user-stats { user: tx-sender })
                        ))
                        (rep-bonus (/ winnings u1000000)) ;; 1 rep point per STX won
                    )
                    (map-set user-stats { user: tx-sender } {
                        total-bets: (get total-bets current-user-stats),
                        total-wagered: (get total-wagered current-user-stats),
                        total-winnings: (+ (get total-winnings current-user-stats) winnings),
                        markets-created: (get markets-created current-user-stats),
                        successful-predictions: (+ (get successful-predictions current-user-stats) u1),
                        reputation-score: (+ (get reputation-score current-user-stats) rep-bonus),
                    })
                )

                (ok winnings)
            )
        )
    )
)

;; Dispute mechanism functions

;; Initiate a dispute for a market resolution
(define-public (initiate-dispute
        (market-id uint)
        (proposed-outcome uint)
        (stake uint)
    )
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-MARKET-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-MARKET-NOT-FOUND)
        
        (let (
                (market (unwrap! (map-get? markets { market-id: market-id }) ERR-MARKET-NOT-FOUND))
                (existing-dispute (map-get? disputes { market-id: market-id }))
            )
            ;; Validate dispute conditions
            (asserts! (get resolved market) ERR-MARKET-NOT-RESOLVED)
            (asserts! (is-none existing-dispute) ERR-DISPUTE-ALREADY-EXISTS)
            (asserts! (>= stake MIN-DISPUTE-STAKE) ERR-INSUFFICIENT-AMOUNT)
            (asserts! (< proposed-outcome (len (get outcomes market))) ERR-INVALID-OUTCOME)
            
            ;; Check if dispute period is still active
            (asserts! 
                (match (get dispute-end-time market)
                    dispute-end (< stacks-block-height dispute-end)
                    false
                )
                ERR-DISPUTE-PERIOD-EXPIRED
            )

            ;; Transfer dispute stake to contract
            (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))

            ;; Create dispute record
            (map-set disputes { market-id: market-id } {
                challenger: tx-sender,
                proposed-outcome: proposed-outcome,
                stake: stake,
                created-at: stacks-block-height,
                votes-for: u0,
                votes-against: u0,
                resolved: false,
            })

            ;; Mark market as disputed
            (map-set markets { market-id: market-id }
                (merge market { disputed: true })
            )

            (ok true)
        )
    )
)

;; Vote on a dispute
(define-public (vote-on-dispute
        (market-id uint)
        (support-dispute bool)
        (vote-stake uint)
    )
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-DISPUTE-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-DISPUTE-NOT-FOUND)
        
        (let (
                (dispute (unwrap! (map-get? disputes { market-id: market-id }) ERR-DISPUTE-NOT-FOUND))
                (existing-vote (map-get? dispute-votes {
                    market-id: market-id,
                    voter: tx-sender,
                }))
            )
            ;; Validate vote conditions
            (asserts! (not (get resolved dispute)) ERR-MARKET-RESOLVED)
            (asserts! (is-none existing-vote) ERR-ALREADY-WITHDRAWN)
            (asserts! (>= vote-stake MIN-BET-AMOUNT) ERR-INSUFFICIENT-AMOUNT)

            ;; Transfer vote stake to contract
            (try! (stx-transfer? vote-stake tx-sender (as-contract tx-sender)))

            ;; Record vote
            (map-set dispute-votes {
                market-id: market-id,
                voter: tx-sender,
            } {
                vote: support-dispute,
                stake: vote-stake,
            })

            ;; Update dispute vote tallies
            (map-set disputes { market-id: market-id }
                (merge dispute {
                    votes-for: (if support-dispute 
                        (+ (get votes-for dispute) vote-stake)
                        (get votes-for dispute)
                    ),
                    votes-against: (if support-dispute
                        (get votes-against dispute)
                        (+ (get votes-against dispute) vote-stake)
                    )
                })
            )

            (ok true)
        )
    )
)

;; Resolve dispute (contract owner only)
(define-public (resolve-dispute
        (market-id uint)
        (uphold-dispute bool)
    )
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-MARKET-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-MARKET-NOT-FOUND)
        
        (let (
                (market (unwrap! (map-get? markets { market-id: market-id }) ERR-MARKET-NOT-FOUND))
                (dispute (unwrap! (map-get? disputes { market-id: market-id }) ERR-DISPUTE-NOT-FOUND))
            )
            ;; Only contract owner can resolve disputes
            (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
            (asserts! (not (get resolved dispute)) ERR-MARKET-RESOLVED)

            ;; Update dispute as resolved
            (map-set disputes { market-id: market-id }
                (merge dispute { resolved: true })
            )

            (if uphold-dispute
                ;; If dispute is upheld, update market with new outcome
                (begin
                    (map-set markets { market-id: market-id }
                        (merge market { 
                            winning-outcome: (some (get proposed-outcome dispute)),
                            disputed: false,
                        })
                    )
                    ;; Return dispute stake to challenger
                    (try! (as-contract (stx-transfer? (get stake dispute) tx-sender (get challenger dispute))))
                )
                ;; If dispute is rejected, keep original resolution
                (begin
                    (map-set markets { market-id: market-id }
                        (merge market { disputed: false })
                    )
                    ;; Forfeit dispute stake (goes to platform)
                    (var-set accumulated-fees (+ (var-get accumulated-fees) (get stake dispute)))
                )
            )

            (ok uphold-dispute)
        )
    )
)

;; Platform fee management functions

;; Set platform fee rate (contract owner only)
(define-public (set-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate MAX-PLATFORM-FEE) ERR-INSUFFICIENT-AMOUNT)
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)

;; Collect accumulated platform fees (contract owner only)
(define-public (collect-fees)
    (let ((fees (var-get accumulated-fees)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> fees u0) ERR-INSUFFICIENT-AMOUNT)
        (var-set accumulated-fees u0)
        (try! (as-contract (stx-transfer? fees tx-sender tx-sender)))
        (ok fees)
    )
)

;; Collect fees from specific resolved market (contract owner only)
(define-public (collect-market-fees (market-id uint))
    (begin
        ;; Validate inputs first
        (asserts! (> market-id u0) ERR-MARKET-NOT-FOUND)
        (asserts! (< market-id (var-get next-market-id)) ERR-MARKET-NOT-FOUND)
        
        (let (
                (market (unwrap! (map-get? markets { market-id: market-id }) ERR-MARKET-NOT-FOUND))
                (market-fees (get platform-fees market))
            )
            (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
            (asserts! (get resolved market) ERR-MARKET-NOT-RESOLVED)
            (asserts! (> market-fees u0) ERR-INSUFFICIENT-AMOUNT)
            
            ;; Reset market fees to 0 and add to accumulated fees
            (map-set markets { market-id: market-id }
                (merge market { platform-fees: u0 })
            )
            (var-set accumulated-fees (+ (var-get accumulated-fees) market-fees))
            
            (try! (as-contract (stx-transfer? market-fees tx-sender tx-sender)))
            (ok market-fees)
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

;; Get current platform fee rate
(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

;; Get accumulated platform fees
(define-read-only (get-accumulated-fees)
    (var-get accumulated-fees)
)

;; Dynamic odds calculation functions

;; Get current odds for a specific outcome (returns implied probability * 10000)
(define-read-only (get-outcome-odds (market-id uint) (outcome uint))
    (let (
            (market (unwrap! (map-get? markets { market-id: market-id }) (err u0)))
            (total-pool (get total-pool market))
            (outcome-total (get-outcome-total market-id outcome))
        )
        (if (> total-pool u0)
            (ok (/ (* outcome-total BASIS-POINTS) total-pool))
            (ok u0)
        )
    )
)

;; Calculate potential payout ratio for a bet amount on specific outcome
(define-read-only (calculate-payout-ratio 
        (market-id uint) 
        (outcome uint) 
        (bet-amount uint)
    )
    (let (
            (market (unwrap! (map-get? markets { market-id: market-id }) (err u0)))
            (current-total (get total-pool market))
            (current-outcome-total (get-outcome-total market-id outcome))
            (platform-fees (get platform-fees market))
            (current-fee-rate (var-get platform-fee-rate))
            (additional-fee (/ (* bet-amount current-fee-rate) BASIS-POINTS))
            (projected-total (+ current-total bet-amount))
            (projected-outcome-total (+ current-outcome-total bet-amount))
            (projected-fees (+ platform-fees additional-fee))
            (distributable-pool (- projected-total projected-fees))
        )
        (if (> projected-outcome-total u0)
            (ok (/ (* distributable-pool BASIS-POINTS) projected-outcome-total))
            (ok u0)
        )
    )
)

;; Get dispute information
(define-read-only (get-dispute (market-id uint))
    (map-get? disputes { market-id: market-id })
)

;; Get user's dispute vote
(define-read-only (get-dispute-vote (market-id uint) (voter principal))
    (map-get? dispute-votes {
        market-id: market-id,
        voter: voter,
    })
)

;; Category management functions

;; Get category statistics
(define-read-only (get-category-stats (category uint))
    (default-to 
        { total-markets: u0, active-markets: u0, total-volume: u0 }
        (map-get? category-stats { category: category })
    )
)

;; Get category name as string
(define-read-only (get-category-name (category uint))
    (if (is-eq category CATEGORY-SPORTS) (some "Sports")
    (if (is-eq category CATEGORY-POLITICS) (some "Politics")
    (if (is-eq category CATEGORY-CRYPTO) (some "Cryptocurrency")
    (if (is-eq category CATEGORY-ENTERTAINMENT) (some "Entertainment")
    (if (is-eq category CATEGORY-TECHNOLOGY) (some "Technology")
    (if (is-eq category CATEGORY-FINANCE) (some "Finance")
    (if (is-eq category CATEGORY-OTHER) (some "Other")
        none
    )))))))
)

;; Get all category statistics
(define-read-only (get-all-category-stats)
    (ok {
        sports: (get-category-stats CATEGORY-SPORTS),
        politics: (get-category-stats CATEGORY-POLITICS),
        crypto: (get-category-stats CATEGORY-CRYPTO),
        entertainment: (get-category-stats CATEGORY-ENTERTAINMENT),
        technology: (get-category-stats CATEGORY-TECHNOLOGY),
        finance: (get-category-stats CATEGORY-FINANCE),
        other: (get-category-stats CATEGORY-OTHER),
    })
)

;; User statistics functions

;; Get user statistics
(define-read-only (get-user-stats (user principal))
    (default-to 
        { total-bets: u0, total-wagered: u0, total-winnings: u0, markets-created: u0, successful-predictions: u0, reputation-score: u0 }
        (map-get? user-stats { user: user })
    )
)

;; Calculate user win rate
(define-read-only (get-user-win-rate (user principal))
    (let (
            (stats (get-user-stats user))
            (total-bets (get total-bets stats))
            (successful-predictions (get successful-predictions stats))
        )
        (if (> total-bets u0)
            (/ (* successful-predictions BASIS-POINTS) total-bets)
            u0
        )
    )
)

;; Get user profit/loss
(define-read-only (get-user-profit-loss (user principal))
    (let (
            (stats (get-user-stats user))
            (total-wagered (get total-wagered stats))
            (total-winnings (get total-winnings stats))
        )
        (if (>= total-winnings total-wagered)
            (ok (- total-winnings total-wagered))
            (err (- total-wagered total-winnings))
        )
    )
)

;; Get user reputation tier
(define-read-only (get-user-reputation-tier (user principal))
    (let ((rep-score (get reputation-score (get-user-stats user))))
        (if (>= rep-score u1000) "Legend"
        (if (>= rep-score u500) "Expert" 
        (if (>= rep-score u100) "Experienced"
        (if (>= rep-score u25) "Active"
            "Newcomer"
        ))))
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