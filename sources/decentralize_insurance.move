module decentralized_insurance::insurance {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self};
    use sui::object::{Self, UID, ID};
    use sui::transfer::{Self};
    use sui::event;
    use std::vector;

    // Error Definitions
    const INSUFFICIENT_BALANCE: u64 = 1;
    const CLAIM_NOT_VERIFIED: u64 = 2;
    const CLAIMANT_CANNOT_VERIFY: u64 = 4;
    const VERIFIER_ALREADY_VERIFIED: u64 = 5;
    const CLAIM_CONDITIONS_NOT_MET: u64 = 6;
    const POLICY_IS_ACTIVE: u64 = 7;
    const INSUFFICIENT_POOL_BALANCE: u64 = 8;
    const AMOUNT_IS_LESS_THAN_THE_PREMIUM: u64 = 9;
    
    // Struct representing an insurance policy
    struct Policy has key, store {
        id: UID,
        owner: address,
        premium: u64,
        coverage: u64,
        conditions: vector<u8>,
        is_active: bool,
    }
    
    // Struct representing a claim
    struct Claim has key, store {
        id: UID,
        policy_id: u64,
        claimant: address,
        verifiers: vector<address>,
        amount: u64,
        is_verified: bool,
        is_paid: bool,
    }

    // Struct representing a community pool
    struct CommunityPool has key, store {
        id: UID,
        balance: u64,
        stakers: vector<address>,
    }

    // Events
    struct PolicyCreated has copy, drop { owner: address, premium: u64, coverage: u64, conditions: vector<u8> }
    struct ClaimCreated has copy, drop { id: UID, policy_id: u64 }
    struct ClaimPaid has copy, drop { id: UID, amount: u64 }
    
    // Create a new insurance policy
    public fun create_policy(owner: address, premium: u64, coverage: u64, conditions: vector<u8>, ctx: &mut TxContext): Policy {
        let policy_id = object::new(ctx);
        let policy = Policy {
            id: policy_id,
            owner,
            premium,
            coverage,
            conditions,
            is_active: true,
        };
        event::emit(PolicyCreated { 
            owner,
            premium,
            coverage,
            conditions,
        });
        policy
    }
    
    // Pay premium for an insurance policy
    public fun pay_premium(policy: &mut Policy, payment: Coin<SUI>, ctx: &mut TxContext) {
        assert!(policy.is_active, POLICY_IS_ACTIVE);
        assert!(coin::value(&payment) >= policy.premium, AMOUNT_IS_LESS_THAN_THE_PREMIUM);
        let payer = tx_context::sender(ctx);
        policy.owner = payer;
        policy.is_active = true;
        transfer::public_transfer(payment, policy.owner);
        event::emit(PolicyCreated { 
            owner: payer,
            premium: policy.premium,
            coverage: policy.coverage,
            conditions: policy.conditions,
        });
    }
    
    // Create a new claim
    public fun create_claim(policy_id: u64, claimant: address, amount: u64, ctx: &mut TxContext): Claim {
        let claim_id = object::new(ctx);
        let claim = Claim {
            id: claim_id,
            policy_id,
            claimant,
            verifiers: vector::empty<address>(),
            amount,
            is_verified: false,
            is_paid: false,
        };
        event::emit(ClaimCreated { id: claim_id, policy_id });
        claim
    }
    
    // Verify a claim
    public fun verify_claim(claim: &mut Claim, verifier: address) {
        assert!(verifier != claim.claimant, CLAIMANT_CANNOT_VERIFY);
        assert!(!vector::contains(&claim.verifiers, &verifier), VERIFIER_ALREADY_VERIFIED);
        
        let all_conditions_met = true;  // Placeholder for actual condition checks
        assert!(all_conditions_met, CLAIM_CONDITIONS_NOT_MET);
        
        vector::push_back(&mut claim.verifiers, verifier);
        
        if (vector::length(&claim.verifiers) > 1) {
            claim.is_verified = true;
        }
    }
    
    // Pay a verified claim
    public fun pay_claim(claim: &mut Claim, pool: &mut CommunityPool, ctx: &mut TxContext) {
        assert!(claim.is_verified, CLAIM_NOT_VERIFIED);
        assert!(pool.balance >= claim.amount, INSUFFICIENT_POOL_BALANCE);
        
        claim.is_paid = true;
        pool.balance -= claim.amount;
        let payment = coin::new(claim.amount, ctx);
        transfer::public_transfer(payment, claim.claimant);
        event::emit(ClaimPaid { id: claim.id, amount: claim.amount });
    }
    
    // Create a community pool
    public fun create_community_pool(initial_balance: u64, ctx: &mut TxContext): CommunityPool {
        let pool_id = object::new(ctx);
        CommunityPool {
            id: pool_id,
            balance: initial_balance,
            stakers: vector::empty<address>(),
        }
    }
    
    // Stake tokens in a community pool
    public fun stake(pool: &mut CommunityPool, staker: address, amount: u64) {
        pool.balance += amount;
        vector::push_back(&mut pool.stakers, staker);
    }

    // Function to get policy details (example of an additional function)
    public fun get_policy_details(policy: &Policy): (address, u64, u64, vector<u8>, bool) {
        (policy.owner, policy.premium, policy.coverage, policy.conditions, policy.is_active)
    }
    
    // Function to get claim details (example of an additional function)
    public fun get_claim_details(claim: &Claim): (u64, address, vector<address>, u64, bool, bool) {
        (claim.policy_id, claim.claimant, claim.verifiers, claim.amount, claim.is_verified, claim.is_paid)
    }
}
