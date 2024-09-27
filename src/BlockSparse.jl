######## Takes a matrix of matrices (a pattern of blocks), and assembles it into a bigmat

# i index
# n length
# p ptr (using the colptr compression convention - the index of start of a swath within a vector)
#
# b block  - indexing blocks within pattern
# l local  - indexing entries inside a block
# g global - indexing the whole bigmat
#
# r row
# c col
# v non-zero value
#
# sparse.rowval → ilr
# sparse.colptr → pilr  
# ilv    = pilr[ilc]+ i-1
# irow   = ilr[ilv]  

"""
    bigmat,bigmatasm,bigvacasm,bigvecdis = prepare(pattern)

Prepare for the assembly of sparse blocks into a large sparse matrix. 
`bigmat` is allocated, with the correct sparsity structure, but its `nzval` undef'ed.    
Where some blocks share the same sparsity structure, `blocks` in `pattern` can have `===` elements.

`pattern` is a `SparseMatrixCSC{<:SparseMatrixCSC}`, where empty blocks are structuraly zero

See also: [`addin!`](@ref)
""" 
function prepare(pattern::SparseMatrixCSC{SparseMatrixCSC{Tv,𝕫},𝕫}) where{Tv} 
    nbr,nbc                       = size(pattern)
    nbr>0 && nbc>0 || muscadeerror("must have length(pattern)>0")
    nlr                           = [-1 for ibr=1:nbr+1]
    nlc                           = [-1 for ibc=1:nbc+1]
    ngv                           = 0
    asm_igv                       = Vector{𝕫1}(undef,nnz(pattern))
    for ibc                       = 1:nbc
        for ibv                   = pattern.colptr[ibc]:pattern.colptr[ibc+1]-1
            ibr                   = pattern.rowval[ibv]
            block                 = pattern.nzval[ibv]
            nlr[ibr+1]            = block.m
            nlc[ibc+1]            = block.n
            nlv                   = length(block.nzval)
            ngv                  += nlv
            asm_igv[ibv]          = 𝕫1(undef,nlv)
        end
    end
    nlr[1]                        = 1
    nlc[1]                        = 1
    all(nlr.>0) || muscadeerror("every row of the pattern must contain at least one non-zero block")
    all(nlc.>0) || muscadeerror("every column of the pattern contain at least one non-zero block")
    pgr                           = cumsum(nlr)  # pgr[ibr]→igr global row corresponding to the first local row of each block
    pgc                           = cumsum(nlc)  # pgc[ibc]→igc global column corresponding to the first local row of each block
    ngr                           = pgr[end]-1
    ngc                           = pgc[end]-1

    # create asm and global matrix (gv, aka nzval is undef in global matrix)
    pigr                          = 𝕫1(undef,ngc+1)        # aka global.colptr
    igr                           = 𝕫1(undef,ngv  )        # aka global.rowval
    gv                            = Vector{Tv}(undef,ngv)  # aka global.nzval
    asm                           = Vector{𝕫2}(undef,nbr)  # asm[ibc][ibr,ilc] → igv for a given block, and local column, where does the storage start?
    pigr[1]                       = 1
    igv                           = 1
    for ibc                       = 1:nbc                  # for each block column
        for ilc                   = 1:nlc[ibc+1]           # for each local column
            igc                   = pgc[ibc]-1 + ilc 
            for ibv               = pattern.colptr[ibc]:pattern.colptr[ibc+1]-1 # for each block row
                ibr               = pattern.rowval[ibv]
                block             = pattern.nzval[ibv]
                pilr,ilr          = block.colptr, block.rowval
                for ilv           = pilr[ilc]:pilr[ilc+1]-1 
                    igr[igv]      = pgr[ibr]-1 + ilr[ilv]
                    asm_igv[ibv][ilv] = igv
                    igv          += 1    
                end
            end
            pigr[igc+1]           = igv   
        end
    end
    bigmat    = SparseMatrixCSC(ngr,ngc,pigr,          igr,                gv)
    bigmatasm = SparseMatrixCSC(nbr,nbc,pattern.colptr,pattern.rowval,asm_igv)
    return    bigmat,bigmatasm,pgr,pgc    
end
"""
    addin!(asm,global,block,ibr,ibc,factor=1.)

Add a sparse `block` into a large `out` sparse matrix, at block-row and -column `ibr` and `ibc`.  
   Use [`prepare`](@ref) to allocate memory for `global` and build the assembler `asm`.
""" 
function addin!(asm::SparseMatrixCSC{𝕫1,𝕫},out::SparseMatrixCSC{Tv,Ti},block::SparseMatrixCSC{Tv,Ti},ibr::𝕫,ibc::𝕫,factor::ℝ=1.) where{Tv,Ti<:Integer}
    lo  = asm.colptr[ibc]         # dichotomy to find ibv (index into asm.nzval)
    hi  = asm.colptr[ibc+1]-1
    ibv  = div(lo+hi,2)
    while true
        aibr = asm.rowval[ibv]
        if ibr == aibr       break
        else
            hi == lo && muscadeerror(@sprintf("BlockSparseAssembler pattern has no block [%i,%i]",ibr,ibc))
            if ibr > aibr    lo = ibv+1
            else             hi = ibv-1  
            end
        end
        ibv  = div(lo+hi,2)
    end
    aigv = asm.nzval[ibv]     # addin the block
    for ilv ∈ eachindex(aigv)  
        out.nzval[aigv[ilv]] += block.nzval[ilv] * factor
    end
end


"""
    addin!(asm,outvec,blockvec,ibr)

Add a full `block` vector into a large `outvec` full vector.  at block-row `ibr`.
Use [`prepare`](@ref) to create `asm`.

See also: [`prepare`](@ref)
""" 
function addin!(pgr::𝕫1,out::Vector{Tv},block::Vector{Tv},ibr::𝕫,factor::ℝ=1.) where{Tv}
    for (ilv,igv)∈enumerate(pgr[ibr]:pgr[ibr+1]-1) 
        out[igv] += block[ilv] * factor
    end
end

# disassemble a block from a big-vector
disblock(pgc::𝕫1,v::Vector,ibc::𝕫) = view(v,pgc[ibc]:(pgc[ibc+1]-1))

