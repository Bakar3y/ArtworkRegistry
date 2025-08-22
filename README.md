# ArtworkRegistry

A blockchain-based digital art authentication and provenance tracking system built on Stacks. This smart contract enables curators to create verified digital artwork certificates with complete provenance tracking.

## Features

- **Digital Art Certificates**: Mint NFT certificates for digital artworks
- **Curator Network**: Verified curator system for artwork authentication
- **Provenance Tracking**: Complete history tracking for each artwork
- **Authentication Records**: Professional appraisal and verification system
- **Secure Transfers**: Safe artwork custody transfers between collectors

## Smart Contract Functions

### Administrative
- `update-contract-admin`: Update contract administrator
- `register-curator`: Register as a verified curator
- `revoke-curator-status`: Revoke curator verification

### Artwork Management
- `mint-artwork-certificate`: Create new artwork certificate
- `transfer-artwork-custody`: Transfer artwork to new collector
- `authenticate-artwork`: Add authentication record
- `update-artwork-provenance`: Update artwork history

### Query Functions
- `get-artwork-metadata`: Retrieve artwork details
- `get-artwork-provenance`: Get artwork history
- `get-authentication-record`: View authentication status
- `get-curator-info`: Check curator information

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Register as a curator with your gallery name
3. Start minting artwork certificates for digital art pieces
4. Build provenance records and authentication history

## License

MIT License
\`\`\`

```clarity file="project-2-music/contracts/track-ownership.clar"
;; TrackOwnership - A decentralized music rights and royalty management system
;; This contract allows producers to register music tracks with ownership and royalty distribution

(define-non-fungible-token track-rights uint)

;; Data storage
(define-map track-info uint {song-title: (string-ascii 64), composer: (string-ascii 256), audio-hash: (string-utf8 256)})
(define-map track-credits uint (list 20 {role: (string-ascii 32), contributor: (string-ascii 64)}))
(define-map producer-registry principal {studio-name: (string-ascii 64), active: bool})
(define-map royalty-splits {distributor-id: principal, track-id: uint} {approved: bool, percentage-share: uint})
(define-map track-holders uint principal)

;; Error codes
(define-constant ERR_ACCESS_DENIED (err u100))
(define-constant ERR_PRODUCER_INACTIVE (err u101))
(define-constant ERR_TRACK_NOT_FOUND (err u102))
(define-constant ERR_ALREADY_EXISTS (err u103))
(define-constant ERR_INVALID_INPUT (err u104))
(define-constant ERR_NOT_RIGHTS_HOLDER (err u105))
(define-constant ERR_INVALID_PRINCIPAL (err u106))
(define-constant ERR_EMPTY_STRING (err u107))
(define-constant ERR_INVALID_PERCENTAGE (err u108))

;; Constants
(define-constant ZERO_PRINCIPAL 'SP000000000000000000002Q6VF78)
(define-constant MAX_PERCENTAGE u100)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_ACCESS_DENIED)
    (asserts! (not (is-eq new-owner ZERO_PRINCIPAL)) ERR_INVALID_PRINCIPAL)
    (ok (var-set contract-owner new-owner))))

;; Producer registration
(define-public (register-producer (studio-name (string-ascii 64)))
  (begin
    (asserts! (> (len studio-name) u0) ERR_EMPTY_STRING)
    (let ((producer-data (default-to {studio-name: "", active: false} (map-get? producer-registry tx-sender))))
      (asserts! (not (get active producer-data)) ERR_ALREADY_EXISTS)
      (ok (map-set producer-registry tx-sender {studio-name: studio-name, active: true})))))

(define-public (deactivate-producer)
  (let ((producer-data (default-to {studio-name: "", active: false} (map-get? producer-registry tx-sender))))
    (asserts! (get active producer-data) ERR_PRODUCER_INACTIVE)
    (ok (map-set producer-registry tx-sender 
      {studio-name: (get studio-name producer-data), active: false}))))

;; Track registration
(define-public (register-track 
    (rights-holder principal) 
    (track-id uint) 
    (song-title (string-ascii 64)) 
    (composer (string-ascii 256)) 
    (audio-hash (string-utf8 256)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-some (map-get? producer-registry tx-sender))) ERR_ACCESS_DENIED)
    (asserts! (is-none (nft-get-owner? track-rights track-id)) ERR_ALREADY_EXISTS)
    
    (asserts! (not (is-eq rights-holder ZERO_PRINCIPAL)) ERR_INVALID_PRINCIPAL)
    (asserts! (> (len song-title) u0) ERR_EMPTY_STRING)
    (asserts! (> (len composer) u0) ERR_EMPTY_STRING)
    (asserts! (> (len audio-hash) u0) ERR_EMPTY_STRING)
    
    (try! (nft-mint? track-rights track-id rights-holder))
    (map-set track-info track-id {song-title: song-title, composer: composer, audio-hash: audio-hash})
    (map-set track-holders track-id rights-holder)
    (ok track-id)))

(define-public (transfer-track-rights (track-id uint) (new-holder principal))
  (begin
    (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? track-rights track-id) ERR_TRACK_NOT_FOUND)) ERR_NOT_RIGHTS_HOLDER)
    (asserts! (not (is-eq new-holder ZERO_PRINCIPAL)) ERR_INVALID_PRINCIPAL)
    (try! (nft-transfer? track-rights track-id tx-sender new-holder))
    (map-set track-holders track-id new-holder)
    (ok true)))

;; Royalty management
(define-public (set-royalty-split (track-id uint) (percentage-share uint) (approved bool))
  (begin
    (asserts! (is-some (map-get? producer-registry tx-sender)) ERR_PRODUCER_INACTIVE)
    (asserts! (is-some (nft-get-owner? track-rights track-id)) ERR_TRACK_NOT_FOUND)
    (asserts! (&lt;= percentage-share MAX_PERCENTAGE) ERR_INVALID_PERCENTAGE)
    (ok (map-set royalty-splits {distributor-id: tx-sender, track-id: track-id} 
                {approved: approved, percentage-share: percentage-share}))))

;; Helper functions
(define-private (validate-credit (credit {role: (string-ascii 32), contributor: (string-ascii 64)}))
  (and (> (len (get role credit)) u0) (> (len (get contributor credit)) u0)))

(define-private (validate-credits (credits (list 20 {role: (string-ascii 32), contributor: (string-ascii 64)})))
  (let ((credits-len (len credits)))
    (and 
      (> credits-len u0)
      (is-eq credits-len (len (filter validate-credit credits))))))

;; Track credits
(define-public (set-track-credits (track-id uint) (credits (list 20 {role: (string-ascii 32), contributor: (string-ascii 64)})))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_ACCESS_DENIED)
    (asserts! (is-some (nft-get-owner? track-rights track-id)) ERR_TRACK_NOT_FOUND)
    (asserts! (validate-credits credits) ERR_INVALID_PERCENTAGE)
    (ok (map-set track-credits track-id credits))))

;; Read-only functions
(define-read-only (get-track-info (track-id uint))
  (map-get? track-info track-id))

(define-read-only (get-track-credits (track-id uint))
  (map-get? track-credits track-id))

(define-read-only (get-royalty-split (distributor-id principal) (track-id uint))
  (map-get? royalty-splits {distributor-id: distributor-id, track-id: track-id}))

(define-read-only (get-producer-info (producer-id principal))
  (map-get? producer-registry producer-id))

(define-read-only (get-track-owner (track-id uint))
  (nft-get-owner? track-rights track-id))

(define-read-only (is-producer-active (producer-id principal))
  (match (map-get? producer-registry producer-id)
    producer-data (get active producer-data)
    false))
