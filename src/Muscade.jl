module Muscade
    using  Printf,SparseArrays,StaticArrays,LinearAlgebra

    include("Dialect.jl")
    export ℝ,ℤ,𝕣,𝕫,𝔹,𝕓
    export ℝ1,ℤ1,𝕣1,𝕫1,𝔹1,𝕓1
    export ℝ2,ℤ2,𝕣2,𝕫2,𝔹2,𝕓2
    export ℝ11,ℤ11,𝕣11,𝕫11,𝔹11,𝕓11
    export toggle,@once,default

    include("Adiff.jl")
    export  ∂ℝ #\partial \bbR
    export  variate,δ # \delta
    export  value,VALUE,∂ # \partial, \nabla
    export  constants,precedence,npartial,norm
    export  ≗ #\circeq

    include("Dots.jl")
    export dots,∘₀,∘₁,∘₂,⊗

    include("Espy.jl") 
    export @request
    export makekey,forloop,scalar
    export @espy,@espydbg

    include("Exceptions.jl")
    export muscadeerror

    include("ElementAPI.jl")
    export AbstractElement
    export lagrangian,residual,espyable
    export ∂0,∂1,∂2
    export doflist
    export noχ,noFB

    include("ModelDescription.jl")
    export Model,addnode!,addelement!,setscale!,initialize!,unlock
    export coord,Node,DofID,NodID,EleID
    export getndof,getnele,getdofID,describe,eletyp

    include("BasicElements.jl")
    export off,equal,inequal
    export DofCost,SingleDofCost,ElementCost
    export Constraint,Hold
    export QuickFix,DofLoad

    include("Assemble.jl")
    export Assembly
    
    include("Solve.jl")
    export solve

    include("StaticX.jl")
    export StaticX
    
    include("StaticXUA.jl")
    export StaticXUA

    include("Output.jl")
    export getdof,getresult,findlastassigned

    include("SelfDraw.jl")
    export draw,request2draw

    
    module Unit
        include("Unit.jl")
        export unit,←,→,convert
    end
    module ElTest
        include("ElTest.jl")
        export test_static_element,gradient
    end
end
