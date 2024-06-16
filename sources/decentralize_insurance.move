module decentralized_insurance::insurance {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::transfer::{Self};
    use sui::event;

    use std::vector;

    // Errors Definitions
    const ERROR_CLAIM_NOT_VERIFIED: u64 = 2;
    const ERROR_CLAIMANT_CANNOT_VERIFY: u64 = 4;
    const ERROR_VERIFIER_ALREADY_VERIFIED: u64 = 5;
    // const ERROR_CLAIM_CONDITIONS_NOT_MET: u64 = 6; 
    const ERROR_POLICY_IS_ACTIVE: u64 = 7;
    const ERROR_INSUFFICIENT_POOL_BALANCE: u64 = 8;
    const ERROR_AMOUNT_IS_LESS_THAN_THE_PREMIUM: u64 = 9;
    
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
        balance: Balance<SUI>,
        total_amount: u64,
        stakers: vector<address>,
    }

    struct Account has key, store {
        id: UID,
        owner: address,
        balance: u64
    }

    struct AdminCap has key {
        id: UID
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap{id: object::new(ctx)}, sender(ctx));
    }
    
    // Events
    struct PolicyCreated has copy, drop { owner: address, premium: u64, coverage: u64, conditions: vector<u8>}

    // struct ClaimCreated has copy, drop { id: ID, policy_id: u64 }
    
    // struct ClaimPaid has copy, drop { id: ID, amount: u64 }
    
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

    public fun new_account(ctx: &mut TxContext) : Account {
        Account {
            id: object::new(ctx),
            owner: sender(ctx),
            balance: 0
        }
    }
    
    // Pay premium for an insurance policy
    public fun pay_premium(
        policy: &mut Policy, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext,
        ) {
        assert!(policy.is_active, ERROR_POLICY_IS_ACTIVE);
        assert!(coin::value(&payment) >= policy.premium, ERROR_AMOUNT_IS_LESS_THAN_THE_PREMIUM);
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
        claim
    }
    
    // Verify a claim
    public fun verify_claim(claim: &mut Claim, verifier: address) {
        // Ensure the verifier is not the claimant
        assert!(verifier != claim.claimant, ERROR_CLAIMANT_CANNOT_VERIFY);
        // Ensure the verifier hasn't already verified this claim
        assert!(!vector::contains(&claim.verifiers, &verifier), ERROR_VERIFIER_ALREADY_VERIFIED);
        // Add verifier to the list of verifiers
        vector::push_back(&mut claim.verifiers, verifier);
        // If sufficient verifiers have verified, mark the claim as verified
        if (vector::length(&claim.verifiers) > 1) {  // Example: require 2 verifiers
            claim.is_verified = true;
        };
    }
    
    // Pay a verified claim
    public fun pay_claim(claim: &mut Claim, pool: &mut CommunityPool, payment: Coin<SUI>) {
        assert!(claim.is_verified, ERROR_CLAIM_NOT_VERIFIED);
        assert!(pool.total_amount >= claim.amount, ERROR_INSUFFICIENT_POOL_BALANCE);
        claim.is_paid = true;
        transfer::public_transfer(payment, claim.claimant);
    }
    
    // Create a community pool
    public fun new_pool(_:&AdminCap, ctx: &mut TxContext) {
        transfer::share_object(CommunityPool {
            id: object::new(ctx),
            balance: balance::zero(),
            total_amount: 0,
            stakers: vector::empty<address>(),
        })
    }
    
    // Stake tokens in a community pool
    public fun stake(pool: &mut CommunityPool, acc: &mut Account, coin: Coin<SUI>, ctx: &mut TxContext) {
        let deposit = coin::value(&coin);
        pool.total_amount = pool.total_amount + deposit;
        acc.balance = acc.balance + deposit;
        coin::put(&mut pool.balance, coin);
        if(!vector::contains(&pool.stakers, &sender(ctx))) {
            vector::push_back(&mut pool.stakers, sender(ctx));
        };
    }

    public fun withdraw(pool: &mut CommunityPool, acc: &mut Account, amount: u64, ctx: &mut TxContext) : Coin<SUI> {
        assert!(acc.balance >= amount, ERROR_INSUFFICIENT_POOL_BALANCE);
        let coin = coin::take(&mut pool.balance, amount, ctx);
        pool.total_amount = pool.total_amount - amount;
        acc.balance = acc.balance - amount;
        coin
    }
}