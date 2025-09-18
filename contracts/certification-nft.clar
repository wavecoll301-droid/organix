;; Certification NFT - Organix Organic Certification NFT Contract
;; Manages organic certification NFTs with immutable proof for farmers

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-RECIPIENT (err u103))
(define-constant ERR-CERTIFICATE-EXPIRED (err u104))
(define-constant ERR-INVALID-AUTHORITY (err u105))
(define-constant ERR-CERTIFICATE-REVOKED (err u106))
(define-constant ERR-INVALID-METADATA (err u107))
(define-constant ERR-TRANSFER-RESTRICTED (err u108))
(define-constant ERR-INSUFFICIENT-PERMISSIONS (err u109))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-CERTIFICATE-VALIDITY u31536000) ;; 1 year in seconds
(define-constant MIN-FARM-SIZE u1) ;; Minimum 1 acre
(define-constant MAX-FARM-SIZE u10000) ;; Maximum 10,000 acres

;; Certification status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-EXPIRED u2)
(define-constant STATUS-REVOKED u3)
(define-constant STATUS-SUSPENDED u4)

;; NFT Token Definition
(define-non-fungible-token organic-certificate uint)

;; Data variables
(define-data-var next-token-id uint u1)
(define-data-var total-certificates uint u0)
(define-data-var active-certificates uint u0)
(define-data-var contract-uri (string-ascii 256) "https://organix.certificate/")

;; Certificate metadata structure
(define-map certificate-metadata
  { token-id: uint }
  {
    farm-name: (string-ascii 100),
    farmer-name: (string-ascii 100),
    location: (string-ascii 200),
    farm-size: uint,
    certification-type: (string-ascii 50),
    issued-date: uint,
    expiry-date: uint,
    certifying-authority: principal,
    inspector-id: (string-ascii 50),
    products: (string-ascii 200),
    compliance-level: (string-ascii 30),
    status: uint
  }
)

;; Certificate ownership and transfer history
(define-map certificate-history
  { token-id: uint, history-index: uint }
  {
    previous-owner: (optional principal),
    new-owner: principal,
    transfer-date: uint,
    transfer-reason: (string-ascii 100)
  }
)

;; Track history count per certificate
(define-map certificate-history-count
  { token-id: uint }
  { count: uint }
)

;; Authority permissions
(define-map certified-authorities
  { authority: principal }
  {
    name: (string-ascii 100),
    authorized: bool,
    certificates-issued: uint,
    registration-date: uint,
    authority-type: (string-ascii 50)
  }
)

;; Farm registration system
(define-map registered-farms
  { farm-id: (string-ascii 50) }
  {
    owner: principal,
    farm-name: (string-ascii 100),
    location: (string-ascii 200),
    size: uint,
    registration-date: uint,
    verified: bool
  }
)

;; Certificate verification system
(define-map certificate-verifications
  { token-id: uint, verifier: principal }
  {
    verification-date: uint,
    verification-result: bool,
    notes: (string-ascii 200)
  }
)

;; Public Functions

;; Register a certification authority
(define-public (register-authority (authority principal) 
                                 (name (string-ascii 100)) 
                                 (authority-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-METADATA)
    (asserts! (is-none (map-get? certified-authorities { authority: authority })) ERR-ALREADY-EXISTS)
    
    (map-set certified-authorities
      { authority: authority }
      {
        name: name,
        authorized: true,
        certificates-issued: u0,
        registration-date: stacks-block-height,
        authority-type: authority-type
      }
    )
    
    (ok authority)
  )
)

;; Mint a new organic certification NFT
(define-public (mint-certificate (recipient principal)
                                (farm-name (string-ascii 100))
                                (farmer-name (string-ascii 100))
                                (location (string-ascii 200))
                                (farm-size uint)
                                (certification-type (string-ascii 50))
                                (inspector-id (string-ascii 50))
                                (products (string-ascii 200))
                                (compliance-level (string-ascii 30)))
  (let ((token-id (var-get next-token-id))
        (current-time stacks-block-height)
        (expiry-date (+ current-time MAX-CERTIFICATE-VALIDITY)))
    
    ;; Validation checks
    (asserts! (is-authorized-authority tx-sender) ERR-INVALID-AUTHORITY)
    (asserts! (>= farm-size MIN-FARM-SIZE) ERR-INVALID-METADATA)
    (asserts! (<= farm-size MAX-FARM-SIZE) ERR-INVALID-METADATA)
    (asserts! (> (len farm-name) u0) ERR-INVALID-METADATA)
    (asserts! (> (len farmer-name) u0) ERR-INVALID-METADATA)
    
    ;; Mint NFT
    (try! (nft-mint? organic-certificate token-id recipient))
    
    ;; Store certificate metadata
    (map-set certificate-metadata
      { token-id: token-id }
      {
        farm-name: farm-name,
        farmer-name: farmer-name,
        location: location,
        farm-size: farm-size,
        certification-type: certification-type,
        issued-date: current-time,
        expiry-date: expiry-date,
        certifying-authority: tx-sender,
        inspector-id: inspector-id,
        products: products,
        compliance-level: compliance-level,
        status: STATUS-ACTIVE
      }
    )
    
    ;; Initialize certificate history
    (map-set certificate-history
      { token-id: token-id, history-index: u0 }
      {
        previous-owner: none,
        new-owner: recipient,
        transfer-date: current-time,
        transfer-reason: "Initial certificate issuance"
      }
    )
    
    (map-set certificate-history-count
      { token-id: token-id }
      { count: u1 }
    )
    
    ;; Update counters
    (var-set next-token-id (+ token-id u1))
    (var-set total-certificates (+ (var-get total-certificates) u1))
    (var-set active-certificates (+ (var-get active-certificates) u1))
    
    ;; Update authority statistics
    (update-authority-stats tx-sender)
    
    (ok token-id)
  )
)

;; Transfer certificate with proper authorization
(define-public (transfer-certificate (token-id uint) (sender principal) (recipient principal))
  (let ((certificate (unwrap! (map-get? certificate-metadata { token-id: token-id }) ERR-TOKEN-NOT-FOUND))
        (current-time stacks-block-height))
    
    ;; Validation checks
    (asserts! (is-eq (nft-get-owner? organic-certificate token-id) (some sender)) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq tx-sender sender) 
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status certificate) STATUS-ACTIVE) ERR-CERTIFICATE-REVOKED)
    (asserts! (< current-time (get expiry-date certificate)) ERR-CERTIFICATE-EXPIRED)
    
    ;; Transfer NFT
    (try! (nft-transfer? organic-certificate token-id sender recipient))
    
    ;; Record transfer in history
    (let ((history-count (get-certificate-history-count token-id)))
      (map-set certificate-history
        { token-id: token-id, history-index: history-count }
        {
          previous-owner: (some sender),
          new-owner: recipient,
          transfer-date: current-time,
          transfer-reason: "Certificate ownership transfer"
        }
      )
      
      (map-set certificate-history-count
        { token-id: token-id }
        { count: (+ history-count u1) }
      )
    )
    
    (ok true)
  )
)

;; Revoke a certificate
(define-public (revoke-certificate (token-id uint) (reason (string-ascii 100)))
  (let ((certificate (unwrap! (map-get? certificate-metadata { token-id: token-id }) ERR-TOKEN-NOT-FOUND)))
    
    ;; Only the issuing authority or contract owner can revoke
    (asserts! (or (is-eq tx-sender (get certifying-authority certificate))
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status certificate) STATUS-ACTIVE) ERR-CERTIFICATE-REVOKED)
    
    ;; Update certificate status
    (map-set certificate-metadata
      { token-id: token-id }
      (merge certificate { status: STATUS-REVOKED })
    )
    
    ;; Record revocation in history
    (let ((history-count (get-certificate-history-count token-id))
          (current-owner (unwrap! (nft-get-owner? organic-certificate token-id) ERR-TOKEN-NOT-FOUND)))
      (map-set certificate-history
        { token-id: token-id, history-index: history-count }
        {
          previous-owner: (some current-owner),
          new-owner: current-owner,
          transfer-date: stacks-block-height,
          transfer-reason: reason
        }
      )
      
      (map-set certificate-history-count
        { token-id: token-id }
        { count: (+ history-count u1) }
      )
    )
    
    ;; Update active certificate count
    (var-set active-certificates (- (var-get active-certificates) u1))
    
    (ok true)
  )
)

;; Verify certificate authenticity
(define-public (verify-certificate (token-id uint) (notes (string-ascii 200)))
  (let ((certificate (unwrap! (map-get? certificate-metadata { token-id: token-id }) ERR-TOKEN-NOT-FOUND))
        (current-time stacks-block-height))
    
    ;; Check certificate validity
    (let ((is-valid (and (is-eq (get status certificate) STATUS-ACTIVE)
                        (< current-time (get expiry-date certificate)))))
      
      ;; Record verification
      (map-set certificate-verifications
        { token-id: token-id, verifier: tx-sender }
        {
          verification-date: current-time,
          verification-result: is-valid,
          notes: notes
        }
      )
      
      (ok is-valid)
    )
  )
)

;; Private helper functions

;; Check if sender is an authorized authority
(define-private (is-authorized-authority (authority principal))
  (match (map-get? certified-authorities { authority: authority })
    some-auth (get authorized some-auth)
    false
  )
)

;; Update authority statistics
(define-private (update-authority-stats (authority principal))
  (match (map-get? certified-authorities { authority: authority })
    some-auth (map-set certified-authorities
                { authority: authority }
                (merge some-auth { certificates-issued: (+ (get certificates-issued some-auth) u1) }))
    false
  )
)

;; Get certificate history count
(define-private (get-certificate-history-count (token-id uint))
  (match (map-get? certificate-history-count { token-id: token-id })
    some-count (get count some-count)
    u0
  )
)

;; Read-only functions

;; Get certificate metadata
(define-read-only (get-certificate-metadata (token-id uint))
  (map-get? certificate-metadata { token-id: token-id })
)

;; Get certificate owner
(define-read-only (get-certificate-owner (token-id uint))
  (nft-get-owner? organic-certificate token-id)
)

;; Check if certificate is valid
(define-read-only (is-certificate-valid (token-id uint))
  (match (map-get? certificate-metadata { token-id: token-id })
    some-cert (and (is-eq (get status some-cert) STATUS-ACTIVE)
                   (< stacks-block-height (get expiry-date some-cert)))
    false
  )
)

;; Get authority information
(define-read-only (get-authority-info (authority principal))
  (map-get? certified-authorities { authority: authority })
)

;; Get certificate history
(define-read-only (get-certificate-history (token-id uint) (history-index uint))
  (map-get? certificate-history { token-id: token-id, history-index: history-index })
)

;; Get total certificates issued
(define-read-only (get-total-certificates)
  (var-get total-certificates)
)

;; Get active certificates count
(define-read-only (get-active-certificates)
  (var-get active-certificates)
)

;; Get verification record
(define-read-only (get-verification-record (token-id uint) (verifier principal))
  (map-get? certificate-verifications { token-id: token-id, verifier: verifier })
)

;; Get contract URI
(define-read-only (get-contract-uri)
  (var-get contract-uri)
)

;; Get token URI (standard NFT function)
(define-read-only (get-token-uri (token-id uint))
  (ok (some (concat (var-get contract-uri) (uint-to-ascii token-id))))
)

;; Get last token ID
(define-read-only (get-last-token-id)
  (- (var-get next-token-id) u1)
)

;; Helper function to convert uint to ASCII (simplified)
(define-private (uint-to-ascii (value uint))
  ;; Simplified conversion - in practice would need full implementation
  "token"
)

