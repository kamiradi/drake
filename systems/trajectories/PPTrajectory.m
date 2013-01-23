classdef (InferiorClasses = {?ConstantTrajectory}) PPTrajectory < Trajectory
  
  properties
    pp
  end
  
  methods
    function obj = PPTrajectory(ppform)
      obj = obj@Trajectory(ppform.dim);
      obj.pp = ppform;
      obj.tspan = [min(obj.pp.breaks) max(obj.pp.breaks)];
    end
    function y = eval(obj,t)
      t=max(min(t,obj.tspan(end)),obj.tspan(1));
      y = ppvalSafe(obj.pp,t);  % still benefits from being safe (e.g. for supporting TaylorVar)
    end

    function dtraj = fnder(obj)
      dtraj = PPTrajectory(fnder(obj.pp));
    end
    
    % todo: implement deriv and dderiv here
    
    function mobj = inFrame(obj,frame)
      if (obj.getOutputFrame == frame)
        mobj = obj;
      else
        tf = findTransform(obj.getOutputFrame,frame,struct('throw_error_if_fail',true));
        if isa(tf,'AffineSystem') && getNumStates(tf)==0
          D=tf.D;c=tf.y0;
          mobj = D*obj + c;
          mobj = setOutputFrame(mobj,frame);
        else
          mobj = inFrame@Trajectory(obj,frame);
        end
      end
    end
    
    function obj = shiftTime(obj,offset)
      typecheck(offset,'double');
      sizecheck(offset,[1 1]);
      obj.tspan = obj.tspan + offset;
      obj.pp.breaks = obj.pp.breaks + offset;
    end
    
    function obj = uminus(obj)
      obj.pp.coefs = -obj.pp.coefs;
    end
    
    function t = getBreaks(obj)
      t = obj.pp.breaks;
    end
    
    function traj = ctranspose(traj)
      [breaks,coefs,l,k,d] = unmkpp(traj.pp);
      if length(d)<2
        d = [1 d];
      elseif length(d)>2
        error('ctranspose is not defined for ND arrays');
      else
        coefs = reshape(coefs,[d,l,k]);
        coefs = permute(coefs,[2 1 3 4]);
        d=[d(end),d(1:end-1)];
      end
      traj = PPTrajectory(mkpp(breaks,coefs,d));
    end
    
    function c = plus(a,b)
      if ~isequal(size(a),size(b))
        error('must be the same size');  % should support scalars, too (but don't yet)
      end
      if any(size(a)==0)  % handle the empty case
        c = ConstantTrajectory(zeros(size(a)));
        return;
      end
      if isa(a,'ConstantTrajectory') a=double(a); end
      if isa(b,'ConstantTrajectory') b=double(b); end
      
      if isnumeric(a)  % then only b is a PPTrajectory
        [breaks,coefs,l,k,d] = unmkpp(b.pp);
        if length(d)<2, d=[d 1]; elseif length(d)>2, error('plus is not defined for ND arrays'); end
        coefs = reshape(coefs,[d,l,k]);
        for i=1:l, 
          coefs(:,:,i,end)=a+coefs(:,:,i,end);
        end
        c=PPTrajectory(mkpp(breaks,coefs,[size(a,1) d(2)]));
        return;
      elseif isnumeric(b) % then only a is a PPTrajectory
        [breaks,coefs,l,k,d] = unmkpp(a.pp);
        if length(d)<2, d=[d 1]; elseif length(d)>2, error('plus is not defined for ND arrays'); end
        coefs = reshape(coefs,[d,l,k]);
        for i=1:l,
          coefs(:,:,i,end)=coefs(:,:,i,end)+b;
        end
        c=PPTrajectory(mkpp(breaks,coefs,[d(1) size(b,2)]));
        return;
      end

      
      if ~isa(a,'PPTrajectory') || ~isa(b,'PPTrajectory')
        % kick out to general case if they're not both pp trajectories
        c = plus@Trajectory(a,b);
        return;
      end
      
      [abreaks,acoefs,al,ak,ad] = unmkpp(a.pp);
      [bbreaks,bcoefs,bl,bk,bd] = unmkpp(b.pp);
      
      if ~isequal(abreaks,bbreaks)
        breaks = unique([abreaks,bbreaks]);
        a.pp = pprfn(a.pp,setdiff(breaks,abreaks));
        b.pp = pprfn(b.pp,setdiff(breaks,bbreaks));
        
        [abreaks,acoefs,al,ak,ad] = unmkpp(a.pp);
        [bbreaks,bcoefs,bl,bk,bd] = unmkpp(b.pp);
      end
      if (ak>=bk)
        coefs=acoefs; coefs(:,end-bk+1:end)=coefs(:,end-bk+1:end)+bcoefs;
      else
        coefs=bcoefs; coefs(:,end-ak+1:end)=coefs(:,end-ak+1:end)+acoefs;
      end
      
      c = PPTrajectory(mkpp(abreaks,coefs,ad));
    end
    
    function c = mtimes(a,b)
      if any([size(a,1) size(b,2)]==0)  % handle the empty case
        c = ConstantTrajectory(zeros(size(a,1),size(b,2)));
        return;
      end
      if isa(a,'ConstantTrajectory') a=double(a); end
      if isa(b,'ConstantTrajectory') b=double(b); end
      
      if isnumeric(a)  % then only b is a PPTrajectory
        [breaks,coefs,l,k,d] = unmkpp(b.pp);
        if length(d)<2, d=[d 1]; elseif length(d)>2, error('mtimes is not defined for ND arrays'); end
        if isscalar(a), cd = d; elseif isscalar(b), cd = size(a); else cd = [size(a,1),d(2)]; end
        coefs = reshape(coefs,[d,l,k]);
        for i=1:l, for j=1:k,
          c(:,:,i,j)=a*coefs(:,:,i,j);
        end, end
        c=PPTrajectory(mkpp(breaks,c,cd));
        return;
      elseif isnumeric(b) % then only a is a PPTrajectory
        [breaks,coefs,l,k,d] = unmkpp(a.pp);
        if length(d)<2, d=[d 1]; elseif length(d)>2, error('mtimes is not defined for ND arrays'); end
        if isscalar(a), cd = d; elseif isscalar(b), cd = size(a); else cd = [size(a,1),d(2)]; end
        coefs = reshape(coefs,[d,l,k]);
        for i=1:l, for j=1:k,
          c(:,:,i,j)=coefs(:,:,i,j)*b;
        end, end
        c=PPTrajectory(mkpp(breaks,c,[d(1) size(b,2)]));
        return;
      end

      
      if ~isa(a,'PPTrajectory') || ~isa(b,'PPTrajectory')
        % kick out to general case if they're not both pp trajectories
        c = mtimes@Trajectory(a,b);
        return;
      end
      
%      c = PPTrajectory(fncmb(a.pp,'*',b.pp));  % this seems to fail on simple test cases??
      
      [abreaks,acoefs,al,ak,ad] = unmkpp(a.pp);
      [bbreaks,bcoefs,bl,bk,bd] = unmkpp(b.pp);
      
      if ~isequal(abreaks,bbreaks)
        breaks = unique([abreaks,bbreaks]);
        a.pp = pprfn(a.pp,setdiff(breaks,abreaks));
        b.pp = pprfn(b.pp,setdiff(breaks,bbreaks));
        
        [abreaks,acoefs,al,ak,ad] = unmkpp(a.pp);
        [bbreaks,bcoefs,bl,bk,bd] = unmkpp(b.pp);
%        warning('Drake:PPTrajectory:DifferentBreaks','mtimes for pptrajectories with different breaks not support (yet).  kicking out to function handle version');
%        c = mtimes@Trajectory(a,b);
%        return;
      end
      
      if (length(ad)<2) ad=[ad 1];
      elseif (length(ad)>2) error('mtimes not defined for ND arrays'); end
      if (length(bd)<2) bd=[bd 1];
      elseif (length(bd)>2) error('mtimes not defined for ND arrays'); end
      
      acoefs = reshape(acoefs,[ad,al,ak]);
      bcoefs = reshape(bcoefs,[bd,bl,bk]);
      
%       ( sum a(:,:,j)(t-t0)^(k-j) ) ( sum b(:,:,j)(t-t0)^(k-j) )

      cbreaks = abreaks; % also bbreaks, by our assumption above
      if isscalar(a), cd = bd; elseif isscalar(b) cd = ad; else cd = [ad(1) bd(2)]; end
      cl = al;  % also bl, by our assumption that abreaks==bbreaks
      ck = ak+bk-1;
      
      ccoefs = zeros([cd,cl,ck]);
      for l=1:cl  
        for j=1:ak  % note: could probably vectorize at least the inner loops
          for k=1:bk
%            order_a = ak-j; order_b = bk-k;  order_c = order_a+order*b;
            ccoefs(:,:,l,ck-(ak-j)-(bk-k))=ccoefs(:,:,l,ck-(ak-j)-(bk-k)) + acoefs(:,:,l,j)*bcoefs(:,:,l,k);
          end
        end
      end
      c = PPTrajectory(mkpp(cbreaks,ccoefs,cd));
    end
        
    function c = vertcat(a,varargin)
      typecheck(a,'PPTrajectory'); 
      [breaks,coefs,l,k,d] = unmkpp(a.pp);
      coefs = reshape(coefs,[d,l,k]);
      for i=1:length(varargin)
        if ~isa(varargin{i},'PPTrajectory')
          c = vertcat@Trajectory(a,varagin{:});
          return;
        end
        [breaks2,coefs2,l2,k2,d2]=unmkpp(varargin{i}.pp);
        if ~isequal(d(2:end),d2(2:end))
          error('incompatible dimensions');
        end
        if ~isequal(breaks,breaks2)
          warning('Drake:PPTrajectory:DifferentBreaks','vertcat for pptrajectories with different breaks not support (yet).  kicking out to function handle version');
          c = vertcat@Trajectory(a,varagin{:});
          return;
        end
        d = [d(1)+d2(1),d(2:end)];
        coefs = [coefs; reshape(coefs2,[d2,l2,k2])];
      end
      c = PPTrajectory(mkpp(breaks,coefs,d));
      fr = cellfun(@(a) getOutputFrame(a),varargin,'UniformOutput',false);
      c = setOutputFrame(c,MultiCoordinateFrame({getOutputFrame(a),fr{:}}));
    end
    
    function newtraj = append(obj, trajAtEnd)
      % Append a PPTrajectory to this one, creating a new trajectory that
      % starts where this object starts and ends where the given trajectory
      % ends.
      %
      % This will throw an error if the trajectory to append does not start
      % where the first trajectory ends.  This is useful if you did a bunch
      % of peicewise simulation and now want to combine them into one
      % object.
      %
      % @param trajAtEnd trajectory to append
      % @retval newtraj new PPTrajectory object that is the combination of
      % both trajectories
      
      
      % check for time condition
      firstEnd = obj.pp.breaks(end);
      secondStart = trajAtEnd.pp.breaks(1);
      
      if (firstEnd ~= secondStart)
        keyboard
        error(strcat('Cannot append trajectories that do not start/end at the same time.', ...
          'First trajectory ends at t = ',num2str(firstEnd), ...
          ' but the second trajectory starts at t = ', num2str(secondStart)));
      end
      
      
      % check for join condition (1st trajectory must end where the second
      % trajectory begins)
      
      firstEnd = obj.eval(trajAtEnd.pp.breaks(1));
      secondStart = trajAtEnd.eval(trajAtEnd.pp.breaks(1));
      if max(abs(firstEnd - secondStart)) > 1e-2
        
        error(strcat('Cannot append trajectories that do not start/end at the same spot.', ...
          'First trajectory ends at x = ', mat2str(firstEnd, 3), ...
          ' but the second trajectory starts at x = ', mat2str(secondStart, 3)));
      end
      
      % check for the same dimensions
      if (obj.pp.dim ~= trajAtEnd.pp.dim)
        error(strcat('Cannot append trajectories with different dimensionality.', ...
          'First trajectory has pp.dim = ', num2str(obj.pp.dim), ...
          ' but the second trajectory has pp.dim = ', num2str(trajAtEnd.pp.dim)));
      end
      
      % check for the same dimensions
      if (obj.dim ~= trajAtEnd.dim)
        error(strcat('Cannot append trajectories with different dimensionality.', ...
          'First trajectory has dim = ', num2str(obj.pp.dim), ...
          ' but the second trajectory has dim = ', num2str(trajAtEnd.pp.dim)));
      end
      
      % check for the same order
      if (obj.pp.order ~= trajAtEnd.pp.order)
        error(strcat('Cannot append trajectories with different order.', ...
          'First trajectory has pp.order = ', num2str(obj.pp.order), ...
          ' but the second trajectory has pp.order = ', num2str(trajAtEnd.pp.order)));
      end
      
      
      % check for same umin / umax
      if (obj.umax ~= trajAtEnd.umax)
        error(strcat('Cannot append trajectories with different umax.', ...
          'First trajectory has umax = ', num2str(obj.umax), ...
          ' but the second trajectory has umax = ', num2str(trajAtEnd.umax)));
      end
      
      if (obj.umin ~= trajAtEnd.umin)
        error(strcat('Cannot append trajectories with different umin.', ...
          'First trajectory has umin = ', num2str(obj.umin), ...
          ' but the second trajectory has umin = ', num2str(trajAtEnd.umin)));
      end
      
      
      newtraj = obj;
      
      newtraj.tspan = [min(obj.pp.breaks) max(trajAtEnd.pp.breaks)];
      
      newtraj.pp.dim = obj.pp.dim;
      newtraj.pp.order = obj.pp.order;
      
      newtraj.pp.pieces = obj.pp.pieces + trajAtEnd.pp.pieces;
      
      newtraj.dim = obj.dim;
      
      newtraj.pp.breaks = [obj.pp.breaks trajAtEnd.pp.breaks(2:end)];
      newtraj.pp.coefs = [obj.pp.coefs; trajAtEnd.pp.coefs];
      
      newtraj = setInputLimits(newtraj, obj.umin, obj.umax);
    end % append
    
    % should getParameters and setParameters include the breaks? or just
    % the actual coefficients?  
  end
end
