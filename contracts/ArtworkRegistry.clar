;; ArtworkRegistry - A digital art authentication and provenance tracking system
;; This contract allows curators to create verified digital artwork records with full provenance

(define-non-fungible-token artwork-certificate uint)

;; Data storage
(define-map artwork-metadata uint {title: (string-ascii 64), artist: (string-ascii 256), media-url: (string-utf8 256)})
(define-map artwork-provenance uint (list 20 {event: (string-ascii 32), details: (string-ascii 64)}))
(define-map curator-registry principal {gallery-name: (string-ascii 64), verified: bool})
(define-map authentication-records {authenticator-id: principal, artwork-id: uint} {authenticated: bool, appraisal-value: uint})
(define-map artwork-custody uint principal)

;; Error codes
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_CURATOR_NOT_VERIFIED (err u101))
(define-constant ERR_ARTWORK_NOT_EXISTS (err u102))
(define-constant ERR_DUPLICATE_REGISTRATION (err u103))
(define-constant ERR_INVALID_PARAMETERS (err u104))
(define-constant ERR_NOT_CUSTODIAN (err u105))
(define-constant ERR_INVALID_ADDRESS (err u106))
(define-constant ERR_EMPTY_FIELD (err u107))
(define-constant ERR_VALUE_OUT_OF_RANGE (err u108))

;; Constants
(define-constant NULL_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MAX_APPRAISAL_VALUE u1000000000)

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; Administrative functions
(define-public (update-contract-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (ok (var-set contract-admin new-admin))))

;; Curator management
(define-public (register-curator (gallery-name (string-ascii 64)))
  (begin
    (asserts! (> (len gallery-name) u0) ERR_EMPTY_FIELD)
    (let ((curator-status (default-to {gallery-name: "", verified: false} (map-get? curator-registry tx-sender))))
      (asserts! (not (get verified curator-status)) ERR_DUPLICATE_REGISTRATION)
      (ok (map-set curator-registry tx-sender {gallery-name: gallery-name, verified: true})))))

(define-public (revoke-curator-status)
  (let ((curator-status (default-to {gallery-name: "", verified: false} (map-get? curator-registry tx-sender))))
    (asserts! (get verified curator-status) ERR_CURATOR_NOT_VERIFIED)
    (ok (map-set curator-registry tx-sender 
      {gallery-name: (get gallery-name curator-status), verified: false}))))

;; NFT operations
(define-public (mint-artwork-certificate 
    (collector principal) 
    (artwork-id uint) 
    (title (string-ascii 64)) 
    (artist (string-ascii 256)) 
    (media-url (string-utf8 256)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-admin)) 
                 (is-some (map-get? curator-registry tx-sender))) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (is-none (nft-get-owner? artwork-certificate artwork-id)) ERR_DUPLICATE_REGISTRATION)
    
    (asserts! (not (is-eq collector NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (asserts! (> (len title) u0) ERR_EMPTY_FIELD)
    (asserts! (> (len artist) u0) ERR_EMPTY_FIELD)
    (asserts! (> (len media-url) u0) ERR_EMPTY_FIELD)
    
    (try! (nft-mint? artwork-certificate artwork-id collector))
    (map-set artwork-metadata artwork-id {title: title, artist: artist, media-url: media-url})
    (map-set artwork-custody artwork-id collector)
    (ok artwork-id)))

(define-public (transfer-artwork-custody (artwork-id uint) (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? artwork-certificate artwork-id) ERR_ARTWORK_NOT_EXISTS)) ERR_NOT_CUSTODIAN)
    (asserts! (not (is-eq new-collector NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (try! (nft-transfer? artwork-certificate artwork-id tx-sender new-collector))
    (map-set artwork-custody artwork-id new-collector)
    (ok true)))

;; Authentication functions
(define-public (authenticate-artwork (artwork-id uint) (appraisal-value uint) (authenticated bool))
  (begin
    (asserts! (is-some (map-get? curator-registry tx-sender)) ERR_CURATOR_NOT_VERIFIED)
    (asserts! (is-some (nft-get-owner? artwork-certificate artwork-id)) ERR_ARTWORK_NOT_EXISTS)
    (asserts! (<= appraisal-value MAX_APPRAISAL_VALUE) ERR_VALUE_OUT_OF_RANGE)
    (ok (map-set authentication-records {authenticator-id: tx-sender, artwork-id: artwork-id} 
                {authenticated: authenticated, appraisal-value: appraisal-value}))))

;; Helper functions
(define-private (validate-provenance-entry (entry {event: (string-ascii 32), details: (string-ascii 64)}))
  (and (> (len (get event entry)) u0) (> (len (get details entry)) u0)))

(define-private (validate-provenance-list (entries (list 20 {event: (string-ascii 32), details: (string-ascii 64)})))
  (let ((entries-count (len entries)))
    (and 
      (> entries-count u0)
      (is-eq entries-count (len (filter validate-provenance-entry entries))))))

;; Provenance management
(define-public (update-artwork-provenance (artwork-id uint) (provenance (list 20 {event: (string-ascii 32), details: (string-ascii 64)})))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (is-some (nft-get-owner? artwork-certificate artwork-id)) ERR_ARTWORK_NOT_EXISTS)
    (asserts! (validate-provenance-list provenance) ERR_VALUE_OUT_OF_RANGE)
    (ok (map-set artwork-provenance artwork-id provenance))))

;; Query functions
(define-read-only (get-artwork-metadata (artwork-id uint))
  (map-get? artwork-metadata artwork-id))

(define-read-only (get-artwork-provenance (artwork-id uint))
  (map-get? artwork-provenance artwork-id))

(define-read-only (get-authentication-record (authenticator-id principal) (artwork-id uint))
  (map-get? authentication-records {authenticator-id: authenticator-id, artwork-id: artwork-id}))

(define-read-only (get-curator-info (curator-id principal))
  (map-get? curator-registry curator-id))

(define-read-only (get-artwork-owner (artwork-id uint))
  (nft-get-owner? artwork-certificate artwork-id))

(define-read-only (is-curator-verified (curator-id principal))
  (match (map-get? curator-registry curator-id)
    curator-data (get verified curator-data)
    false))